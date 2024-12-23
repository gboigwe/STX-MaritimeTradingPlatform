;; GPS Oracle Contract for Maritime Trading Platform

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-coordinates (err u101))
(define-constant err-unauthorized-oracle (err u102))
(define-constant err-vessel-not-found (err u103))
(define-constant err-outside-geofence (err u104))
(define-constant err-invalid-input (err u105))
(define-constant err-invalid-zone-type (err u106))
(define-constant err-invalid-oracle (err u107))
(define-constant err-oracle-exists (err u108))

;; Data Maps
(define-map authorized-oracles 
    { oracle: principal } 
    { is-active: bool }
)

(define-map geofence-zones
    { zone-id: (string-utf8 36) }
    {
        center-latitude: int,
        center-longitude: int,
        radius: uint,  ;; in meters
        zone-type: (string-ascii 20)  ;; e.g., "port", "trading", "restricted"
    }
)

;; Input Validation Functions
(define-private (is-valid-zone-type (zone-type (string-ascii 20)))
    (or
        (is-eq zone-type "port")
        (is-eq zone-type "trading")
        (is-eq zone-type "restricted")
    )
)

(define-private (is-valid-string-length (str (string-utf8 36)))
    (and 
        (>= (len str) u1)
        (<= (len str) u36)
    )
)

;; Helper Functions
(define-private (calculate-distance-simplified 
    (lat1 int) 
    (lon1 int) 
    (lat2 int) 
    (lon2 int))
    ;; Simplified distance calculation using Manhattan distance
    ;; Returns approximate distance in coordinate units
    (let
        (
            (lat-diff (if (> lat2 lat1)
                (- lat2 lat1)
                (- lat1 lat2)))
            (lon-diff (if (> lon2 lon1)
                (- lon2 lon1)
                (- lon1 lon2)))
        )
        (to-uint (+ lat-diff lon-diff))
    )
)

;; Public Functions
(define-public (register-oracle (oracle principal))
    (begin
        ;; Check that caller is contract owner
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        ;; Verify oracle is not tx-sender
        (asserts! (not (is-eq oracle tx-sender)) err-invalid-oracle)
        
        ;; Check oracle is not null/zero address
        (asserts! (not (is-eq oracle 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)) err-invalid-oracle)
        
        ;; Check if oracle is already registered
        (asserts! (is-none (map-get? authorized-oracles {oracle: oracle})) err-oracle-exists)
        
        ;; If all checks pass, register the oracle
        (ok (map-set authorized-oracles
            {oracle: oracle}
            {is-active: true}
        ))
    )
)

(define-public (update-vessel-location
    (vessel-id (string-utf8 36))
    (new-latitude int)
    (new-longitude int))
    (let
        ((oracle tx-sender))
        ;; Input validation
        (asserts! (is-valid-string-length vessel-id) err-invalid-input)
        (asserts! (is-some (map-get? authorized-oracles {oracle: oracle})) err-unauthorized-oracle)
        
        ;; Coordinate validation
        (asserts! (and 
            (>= new-latitude (* -90 1000000))
            (<= new-latitude (* 90 1000000))
            (>= new-longitude (* -180 1000000))
            (<= new-longitude (* 180 1000000))
        ) err-invalid-coordinates)
        
        ;; Update location in the main contract
        (contract-call? 
            .Maritime-Trading 
            update-vessel-location 
            vessel-id 
            new-latitude 
            new-longitude
        )
    )
)

(define-public (add-geofence-zone
    (zone-id (string-utf8 36))
    (latitude int)
    (longitude int)
    (radius uint)
    (zone-type (string-ascii 20)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        ;; Input validation
        (asserts! (is-valid-string-length zone-id) err-invalid-input)
        (asserts! (is-valid-zone-type zone-type) err-invalid-zone-type)
        (asserts! (> radius u0) err-invalid-input)
        (asserts! (and 
            (>= latitude (* -90 1000000))
            (<= latitude (* 90 1000000))
            (>= longitude (* -180 1000000))
            (<= longitude (* 180 1000000))
        ) err-invalid-coordinates)
        
        (map-set geofence-zones
            {zone-id: zone-id}
            {
                center-latitude: latitude,
                center-longitude: longitude,
                radius: radius,
                zone-type: zone-type
            }
        )
        (ok true)
    )
)

;; Read-Only Functions
(define-read-only (check-vessel-in-zone 
    (vessel-latitude int)
    (vessel-longitude int)
    (zone-id (string-utf8 36)))
    (begin
        (asserts! (is-valid-string-length zone-id) err-invalid-input)
        (ok (match (map-get? geofence-zones {zone-id: zone-id})
            zone-data
            (let
                ((distance (calculate-distance-simplified
                    vessel-latitude
                    vessel-longitude
                    (get center-latitude zone-data)
                    (get center-longitude zone-data)
                )))
                (<= distance (get radius zone-data))
            )
            false
        ))
    )
)

(define-read-only (is-oracle-authorized (oracle principal))
    (match (map-get? authorized-oracles {oracle: oracle})
        data (get is-active data)
        false
    )
)
