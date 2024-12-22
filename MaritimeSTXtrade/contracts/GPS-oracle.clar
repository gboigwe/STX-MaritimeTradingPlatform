;; GPS Oracle Contract for Maritime Trading Platform

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-coordinates (err u101))
(define-constant err-unauthorized-oracle (err u102))
(define-constant err-vessel-not-found (err u103))
(define-constant err-outside-geofence (err u104))

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

;; Helper Functions
(define-private (calculate-distance-simplified 
    (lat1 int) 
    (lon1 int) 
    (lat2 int) 
    (lon2 int))
    ;; Simplified distance calculation using Manhattan distance
    ;; Returns approximate distance in coordinate units
    ;; Note: This is a rough approximation suitable for basic proximity checks
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
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set authorized-oracles
            {oracle: oracle}
            {is-active: true}
        )
        (ok true)
    )
)

(define-public (update-vessel-location
    (vessel-id (string-utf8 36))
    (new-latitude int)
    (new-longitude int))
    (let
        ((oracle tx-sender)
         (vessel-data (contract-call? .Maritime-Trading get-vessel-by-id vessel-id)))
        (asserts! (is-some (map-get? authorized-oracles {oracle: oracle})) err-unauthorized-oracle)
        (asserts! (is-some vessel-data) err-vessel-not-found)
        ;; Define coordinate bounds (-90 to +90 for latitude, -180 to +180 for longitude)
        ;; Using regular integers multiplied by 1000000 for precision
        (asserts! (and 
            (>= new-latitude (* -90 1000000))
            (<= new-latitude (* 90 1000000))
            (>= new-longitude (* -180 1000000))
            (<= new-longitude (* 180 1000000))
        ) err-invalid-coordinates)
        
        ;; Update location in the main contract
        (as-contract 
            (contract-call? 
                .Maritime-Trading 
                update-vessel-location 
                vessel-id 
                new-latitude 
                new-longitude
            )
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
    (match (map-get? geofence-zones {zone-id: zone-id})
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
    )
)

(define-read-only (is-oracle-authorized (oracle principal))
    (match (map-get? authorized-oracles {oracle: oracle})
        data (get is-active data)
        false
    )
)
