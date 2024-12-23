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

;; Input Validation Functions
(define-private (is-valid-string-length (str (string-ascii 50)) (min-len uint) (max-len uint))
    (let
        ((str-len (len str)))
        (and 
            (>= str-len min-len)
            (<= str-len max-len)
        )
    )
)

(define-private (is-valid-document-type (doc-type (string-ascii 50)))
    (or 
        (is-eq doc-type DOCUMENT_TYPE_BILL_OF_LADING)
        (is-eq doc-type DOCUMENT_TYPE_CARGO_MANIFEST)
        (is-eq doc-type DOCUMENT_TYPE_CUSTOMS_DECLARATION)
    )
)

(define-private (is-valid-trade-id (trade-id (string-utf8 36)))
    (and
        (>= (len trade-id) u1)
        (<= (len trade-id) u36)
    )
)

(define-private (is-valid-port-code (port-code (string-ascii 50)))
    (and
        (>= (len port-code) u3)  ;; Minimum length for port codes
        (<= (len port-code) u50)
    )
)

(define-private (is-valid-jurisdiction (jurisdiction (string-ascii 50)))
    (and
        (>= (len jurisdiction) u2)
        (<= (len jurisdiction) u50)
    )
)

(define-private (is-valid-buffer-length (buf (buff 32)))
    (is-eq (len buf) u32)
)

(define-private (is-valid-notes (notes (optional (string-utf8 500))))
    (match notes
        note-text (and 
            (>= (len note-text) u1)
            (<= (len note-text) u500)
        )
        true
    )
)

(define-private (check-document-types (doc-type (string-ascii 50)) (prev-result bool))
    (and prev-result (is-valid-document-type doc-type))
)

;; Authorization Functions
(define-public (register-verifier 
    (verifier principal)
    (jurisdiction (string-ascii 50)))
    (begin
        ;; Input validation
        (asserts! (is-valid-jurisdiction jurisdiction) err-invalid-input)
        (asserts! (not (is-eq verifier contract-owner)) err-invalid-verifier)
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (not (is-eq verifier tx-sender)) err-invalid-verifier)
        
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
    (begin
        ;; Input validation
        (asserts! (is-valid-trade-id trade-id) err-invalid-input)
        (asserts! (is-valid-document-type document-type) err-invalid-input)
        (asserts! (is-valid-buffer-length document-hash) err-invalid-input)
        
        (let
            ((existing-doc (map-get? trade-documents {trade-id: trade-id, document-type: document-type}))
             (trade-response (contract-call? .Maritime-Trading get-trade-agreement trade-id)))
            
            ;; Validate trade exists and permissions
            (asserts! (is-ok trade-response) err-trade-not-found)
            (let 
                ((trade (unwrap! (unwrap-panic trade-response) err-trade-not-found)))
                (asserts! (is-none existing-doc) err-document-exists)
                (asserts! (or 
                    (is-eq tx-sender (get seller trade))
                    (is-eq tx-sender (get buyer trade))
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
    )
)

(define-public (verify-document
    (trade-id (string-utf8 36))
    (document-type (string-ascii 50))
    (verified bool)
    (notes (optional (string-utf8 500))))
    (begin
        ;; Input validation
        (asserts! (is-valid-trade-id trade-id) err-invalid-input)
        (asserts! (is-valid-document-type document-type) err-invalid-input)
        (asserts! (is-valid-notes notes) err-invalid-input)
        
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
)

;; Port Management
(define-public (set-port-requirements
    (port-code (string-ascii 50))
    (required-docs (list 10 (string-ascii 50)))
    (min-verify-time uint)
    (jurisdiction (string-ascii 50)))
    (begin
        ;; Input validation
        (asserts! (is-valid-port-code port-code) err-invalid-input)
        (asserts! (> min-verify-time u0) err-invalid-input)
        (asserts! (is-valid-jurisdiction jurisdiction) err-invalid-input)
        (asserts! (fold check-document-types required-docs true) err-invalid-input)
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
    (begin
        (asserts! (and 
            (is-valid-trade-id trade-id)
            (is-valid-document-type document-type)
        ) err-invalid-input)
        (ok (map-get? trade-documents {trade-id: trade-id, document-type: document-type}))
    )
)

(define-read-only (get-port-requirements (port-code (string-ascii 50)))
    (begin
        (asserts! (is-valid-port-code port-code) err-invalid-input)
        (ok (map-get? port-requirements {port-code: port-code}))
    )
)

(define-read-only (check-trade-compliance
    (trade-id (string-utf8 36))
    (port-code (string-ascii 50)))
    (begin
        (asserts! (is-valid-trade-id trade-id) err-invalid-input)
        (asserts! (is-valid-port-code port-code) err-invalid-input)
        
        (ok (match (map-get? port-requirements {port-code: port-code})
            port-reqs (let
                ((compliance-result (fold check-document-status 
                    (get required-documents port-reqs)
                    {trade-id: trade-id, is-compliant: true})))
                (ok (get is-compliant compliance-result))
            )
            (err err-invalid-input)
        ))
    )
)

(define-private (check-document-status 
    (doc-type (string-ascii 50)) 
    (state {trade-id: (string-utf8 36), is-compliant: bool}))
    (if (get is-compliant state)
        (match (map-get? trade-documents 
            {
                trade-id: (get trade-id state), 
                document-type: doc-type
            })
            doc {
                trade-id: (get trade-id state), 
                is-compliant: (is-eq (get status doc) STATUS_VERIFIED)
            }
            {
                trade-id: (get trade-id state), 
                is-compliant: false
            }
        )
        state
    )
)
