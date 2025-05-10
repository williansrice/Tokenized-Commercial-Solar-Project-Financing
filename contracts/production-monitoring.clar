;; Production Monitoring Contract
;; Records actual energy generation

(define-data-var contract-owner principal tx-sender)

;; Energy production records
(define-map energy-production
  { project-id: uint, period: uint }
  {
    kwh-produced: uint,
    timestamp: uint,
    reporter: principal,
    verified: bool
  }
)

;; Authorized data reporters
(define-map authorized-reporters
  { reporter: principal }
  { authorized: bool }
)

;; Project cumulative production
(define-map project-cumulative
  { project-id: uint }
  { total-kwh: uint, last-period: uint }
)

;; Add a reporter
(define-public (add-reporter (reporter principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403)) ;; Only owner can add reporters
    (map-set authorized-reporters { reporter: reporter } { authorized: true })
    (ok true)
  )
)

;; Remove a reporter
(define-public (remove-reporter (reporter principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403)) ;; Only owner can remove reporters
    (map-delete authorized-reporters { reporter: reporter })
    (ok true)
  )
)

;; Report energy production for a period
(define-public (report-production (project-id uint) (period uint) (kwh-produced uint))
  (let
    ((is-authorized (map-get? authorized-reporters { reporter: tx-sender }))
     (existing-record (map-get? energy-production { project-id: project-id, period: period })))

    (asserts! (is-some is-authorized) (err u403)) ;; Not a reporter
    (asserts! (get authorized (default-to { authorized: false } is-authorized)) (err u403)) ;; Not authorized
    (asserts! (is-none existing-record) (err u1)) ;; Record already exists

    ;; Store the production record
    (map-set energy-production
      { project-id: project-id, period: period }
      {
        kwh-produced: kwh-produced,
        timestamp: block-height,
        reporter: tx-sender,
        verified: false
      }
    )

    ;; Update cumulative production
    (let
      ((cumulative (default-to { total-kwh: u0, last-period: u0 }
                   (map-get? project-cumulative { project-id: project-id }))))
      (map-set project-cumulative
        { project-id: project-id }
        {
          total-kwh: (+ (get total-kwh cumulative) kwh-produced),
          last-period: period
        }
      )
    )

    (ok true)
  )
)

;; Verify a production report
(define-public (verify-production (project-id uint) (period uint))
  (let
    ((record (map-get? energy-production { project-id: project-id, period: period })))
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403)) ;; Only owner can verify
    (asserts! (is-some record) (err u404)) ;; Record not found

    (map-set energy-production
      { project-id: project-id, period: period }
      (merge (default-to
        {
          kwh-produced: u0,
          timestamp: u0,
          reporter: tx-sender,
          verified: false
        }
        record)
        { verified: true }
      )
    )
    (ok true)
  )
)

;; Get production for a specific period
(define-read-only (get-period-production (project-id uint) (period uint))
  (map-get? energy-production { project-id: project-id, period: period })
)

;; Get cumulative production for a project
(define-read-only (get-cumulative-production (project-id uint))
  (map-get? project-cumulative { project-id: project-id })
)

;; Check if a principal is an authorized reporter
(define-read-only (is-reporter (reporter principal))
  (default-to { authorized: false } (map-get? authorized-reporters { reporter: reporter }))
)
