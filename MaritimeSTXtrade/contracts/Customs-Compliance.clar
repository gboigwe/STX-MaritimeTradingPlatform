;; Customs Compliance Contract for Maritime Trading Platform

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-input (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-document-exists (err u103))
(define-constant err-document-not-found (err u104))
(define-constant err-invalid-status (err u105))
(define-constant err-trade-not-found (err u106))
(define-constant err-invalid-verifier (err u107))

;; Document Types and Status
(define-constant DOCUMENT_TYPE_BILL_OF_LADING "bill_of_lading")
(define-constant DOCUMENT_TYPE_CARGO_MANIFEST "cargo_manifest")
(define-constant DOCUMENT_TYPE_CUSTOMS_DECLARATION "customs_declaration")
(define-constant STATUS_PENDING "pending")
(define-constant STATUS_VERIFIED "verified")
(define-constant STATUS_REJECTED "rejected")

;; Data Maps
(define-map authorized-verifiers
    { verifier: principal }
    { 
        is-active: bool,
        jurisdiction: (string-ascii 50)  ;; e.g., "US-PORT-NYC", "SG-PORT-PSA"
    }
)

(define-map trade-documents
    { 
        trade-id: (string-utf8 36),
        document-type: (string-ascii 50)
    }
    {
        hash: (buff 32),  ;; Document hash for verification
        status: (string-ascii 20),
        verifier: (optional principal),
        verification-time: (optional uint),
        notes: (optional (string-utf8 500))
    }
)

(define-map port-requirements
    { port-code: (string-ascii 50) }
    {
        required-documents: (list 10 (string-ascii 50)),
        minimum-verification-time: uint,  ;; in blocks
        authorized-jurisdiction: (string-ascii 50)
    }
)

;; Authorization Functions
(define-public (register-verifier 
    (verifier principal)
    (jurisdiction (string-ascii 50)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (not (is-eq verifier tx-sender)) err-invalid-verifier)
        (asserts! (>= (len jurisdiction) u2) err-invalid-input)
        
        (ok (map-set authorized-verifiers
            {verifier: verifier}
            {
                is-active: true,
                jurisdiction: jurisdiction
            }
        ))
    )
)

;; Document Management
(define-public (submit-document
    (trade-id (string-utf8 36))
    (document-type (string-ascii 50))
    (document-hash (buff 32)))
    (let
        ((existing-doc (map-get? trade-documents {trade-id: trade-id, document-type: document-type}))
         (trade (contract-call? .Maritime-Trading get-trade-agreement trade-id)))
        
        ;; Validate inputs and permissions
        (asserts! (is-some trade) err-trade-not-found)
        (asserts! (is-none existing-doc) err-document-exists)
        (asserts! (or 
            (is-eq tx-sender (get seller (unwrap! trade err-trade-not-found)))
            (is-eq tx-sender (get buyer (unwrap! trade err-trade-not-found)))
        ) err-unauthorized)
        
        (ok (map-set trade-documents
            {trade-id: trade-id, document-type: document-type}
            {
                hash: document-hash,
                status: STATUS_PENDING,
                verifier: none,
                verification-time: none,
                notes: none
            }
        ))
    )
)

(define-public (verify-document
    (trade-id (string-utf8 36))
    (document-type (string-ascii 50))
    (verified bool)
    (notes (optional (string-utf8 500))))
    (let
        ((verifier-info (map-get? authorized-verifiers {verifier: tx-sender}))
         (document (map-get? trade-documents {trade-id: trade-id, document-type: document-type})))
        
        ;; Validate verifier and document
        (asserts! (is-some verifier-info) err-unauthorized)
        (asserts! (get is-active (unwrap! verifier-info err-unauthorized)) err-unauthorized)
        (asserts! (is-some document) err-document-not-found)
        
        (ok (map-set trade-documents
            {trade-id: trade-id, document-type: document-type}
            {
                hash: (get hash (unwrap! document err-document-not-found)),
                status: (if verified STATUS_VERIFIED STATUS_REJECTED),
                verifier: (some tx-sender),
                verification-time: (some block-height),
                notes: notes
            }
        ))
    )
)

;; Port Management
(define-public (set-port-requirements
    (port-code (string-ascii 50))
    (required-docs (list 10 (string-ascii 50)))
    (min-verify-time uint)
    (jurisdiction (string-ascii 50)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set port-requirements
            {port-code: port-code}
            {
                required-documents: required-docs,
                minimum-verification-time: min-verify-time,
                authorized-jurisdiction: jurisdiction
            }
        ))
    )
)

;; Read-Only Functions
(define-read-only (get-document-status
    (trade-id (string-utf8 36))
    (document-type (string-ascii 50)))
    (map-get? trade-documents {trade-id: trade-id, document-type: document-type})
)

(define-read-only (get-port-requirements (port-code (string-ascii 50)))
    (map-get? port-requirements {port-code: port-code})
)

(define-read-only (check-trade-compliance
    (trade-id (string-utf8 36))
    (port-code (string-ascii 50)))
    (let
        ((port-reqs (map-get? port-requirements {port-code: port-code})))
        (if (is-none port-reqs)
            (err err-invalid-input)
            (let
                ((required-docs (get required-documents (unwrap! port-reqs err-invalid-input))))
                (ok (fold check-document-verified-for-trade trade-id required-docs true))
            )
        )
    )
)

(define-private (check-document-verified-for-trade 
    (trade-id (string-utf8 36))
    (doc-type (string-ascii 50)) 
    (prev-result bool))
    (if prev-result
        (match (map-get? trade-documents {trade-id: trade-id, document-type: doc-type})
            doc (is-eq (get status doc) STATUS_VERIFIED)
            false
        )
        false
    )
)
