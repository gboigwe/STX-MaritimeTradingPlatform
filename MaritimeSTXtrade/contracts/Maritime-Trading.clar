;; Maritime Trading Platform Smart Contracts

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-registered (err u101))
(define-constant err-invalid-location (err u102))
(define-constant err-trade-exists (err u103))
(define-constant err-unauthorized-caller (err u104))
(define-constant err-invalid-input (err u105))
(define-constant err-duplicate-vessel (err u106))

;; Input Validation Functions
(define-private (is-valid-string-length (str (string-utf8 36)))
    (and 
        (>= (len str) u1)
        (<= (len str) u36)
    )
)

(define-private (is-valid-registration-number (reg-num (string-utf8 50)))
    (and 
        (>= (len reg-num) u5)  ;; Minimum length for registration numbers
        (<= (len reg-num) u50)
    )
)

(define-private (is-valid-vessel-type (vessel-type (string-utf8 20)))
    (and 
        (>= (len vessel-type) u2)
        (<= (len vessel-type) u20)
    )
)

(define-private (is-valid-cargo-type (cargo-type (string-utf8 50)))
    (and 
        (>= (len cargo-type) u2)
        (<= (len cargo-type) u50)
    )
)

;; Data Variables
(define-map vessels
    { vessel-id: (string-utf8 36) }
    {
        owner: principal,
        registration-number: (string-utf8 50),
        vessel-type: (string-utf8 20),
        max-capacity: uint,
        current-location: {latitude: int, longitude: int},
        is-active: bool
    }
)

(define-map vessel-owner-index 
    { owner: principal } 
    { vessel-id: (string-utf8 36) }
)

(define-map trade-agreements
    { trade-id: (string-utf8 36) }
    {
        seller: principal,
        buyer: principal,
        cargo-type: (string-utf8 50),
        quantity: uint,
        price: uint,
        status: (string-ascii 20),
        completion-location: {latitude: int, longitude: int},
        customs-verified: bool
    }
)

;; Public Functions
(define-public (register-vessel 
    (vessel-id (string-utf8 36))
    (registration-number (string-utf8 50))
    (vessel-type (string-utf8 20))
    (max-capacity uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        ;; Input validation
        (asserts! (is-valid-string-length vessel-id) err-invalid-input)
        (asserts! (is-valid-registration-number registration-number) err-invalid-input)
        (asserts! (is-valid-vessel-type vessel-type) err-invalid-input)
        (asserts! (> max-capacity u0) err-invalid-input)
        ;; Check for duplicate vessel
        (asserts! (is-none (map-get? vessels {vessel-id: vessel-id})) err-duplicate-vessel)
        
        (map-set vessels
            {vessel-id: vessel-id}
            {
                owner: tx-sender,
                registration-number: registration-number,
                vessel-type: vessel-type,
                max-capacity: max-capacity,
                current-location: {latitude: 0, longitude: 0},
                is-active: true
            }
        )
        (map-set vessel-owner-index 
            {owner: tx-sender} 
            {vessel-id: vessel-id}
        )
        (ok true)
    )
)

(define-public (create-trade-agreement
    (trade-id (string-utf8 36))
    (buyer principal)
    (cargo-type (string-utf8 50))
    (quantity uint)
    (price uint)
    (completion-latitude int)
    (completion-longitude int))
    (let
        ((seller tx-sender))
        ;; Input validation
        (asserts! (is-valid-string-length trade-id) err-invalid-input)
        (asserts! (is-valid-cargo-type cargo-type) err-invalid-input)
        (asserts! (and (> quantity u0) (> price u0)) err-invalid-input)
        (asserts! (and 
            (>= completion-latitude (* -90 1000000))
            (<= completion-latitude (* 90 1000000))
            (>= completion-longitude (* -180 1000000))
            (<= completion-longitude (* 180 1000000))
        ) err-invalid-location)
        ;; Check vessel registration
        (asserts! (is-some (get-vessel-for-owner seller)) err-not-registered)
        (asserts! (is-some (get-vessel-for-owner buyer)) err-not-registered)
        ;; Check for duplicate trade agreement
        (asserts! (is-none (map-get? trade-agreements {trade-id: trade-id})) err-trade-exists)
        
        (map-set trade-agreements
            {trade-id: trade-id}
            {
                seller: seller,
                buyer: buyer,
                cargo-type: cargo-type,
                quantity: quantity,
                price: price,
                status: "pending",
                completion-location: {
                    latitude: completion-latitude,
                    longitude: completion-longitude
                },
                customs-verified: false
            }
        )
        (ok true)
    )
)

;; Read-Only Functions
(define-read-only (get-vessel-for-owner (owner principal))
    (match (map-get? vessel-owner-index {owner: owner})
        vessel-index (map-get? vessels {vessel-id: (get vessel-id vessel-index)})
        none
    )
)

(define-read-only (get-vessel-by-id (vessel-id (string-utf8 36)))
    (begin
        (asserts! (is-valid-string-length vessel-id) err-invalid-input)
        (ok (map-get? vessels {vessel-id: vessel-id}))
    )
)

(define-read-only (get-trade-agreement (trade-id (string-utf8 36)))
    (begin
        (asserts! (is-valid-string-length trade-id) err-invalid-input)
        (ok (map-get? trade-agreements {trade-id: trade-id}))
    )
)

;; Add location update function for GPS Oracle
(define-public (update-vessel-location
    (vessel-id (string-utf8 36))
    (new-latitude int)
    (new-longitude int))
    (let
        ((vessel (map-get? vessels {vessel-id: vessel-id})))
        ;; Input validation
        (asserts! (is-valid-string-length vessel-id) err-invalid-input)
        (asserts! (is-some vessel) err-not-registered)
        (asserts! (is-eq contract-caller .GPS-oracle) err-unauthorized-caller)
        (asserts! (and 
            (>= new-latitude (* -90 1000000))
            (<= new-latitude (* 90 1000000))
            (>= new-longitude (* -180 1000000))
            (<= new-longitude (* 180 1000000))
        ) err-invalid-location)
        
        (map-set vessels
            {vessel-id: vessel-id}
            (merge (unwrap! vessel err-not-registered)
                {current-location: 
                    {
                        latitude: new-latitude,
                        longitude: new-longitude
                    }
                }
            )
        )
        (ok true)
    )
)
