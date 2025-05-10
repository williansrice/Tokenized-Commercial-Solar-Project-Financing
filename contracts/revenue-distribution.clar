;; Revenue Distribution Contract
;; Allocates income from energy sales

(define-data-var contract-owner principal tx-sender)

;; Revenue periods
(define-map revenue-periods
  { project-id: uint, period: uint }
  {
    total-revenue: uint,
    distributed: bool,
    distribution-timestamp: uint
  }
)

;; Investor revenue claims
(define-map investor-claims
  { project-id: uint, period: uint, investor: principal }
  {
    amount: uint,
    claimed: bool
  }
)

;; Contract references - simplified to avoid principal literal issues
(define-data-var investment-contract (optional principal) none)

;; Set investment contract reference
(define-public (set-investment-contract (contract-principal principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403)) ;; Only owner can set contract
    (var-set investment-contract (some contract-principal))
    (ok true)
  )
)

;; Record revenue for a period
(define-public (record-revenue (project-id uint) (period uint) (amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403)) ;; Only owner can record revenue
    (asserts! (is-none (map-get? revenue-periods { project-id: project-id, period: period })) (err u1)) ;; Period already exists

    (map-set revenue-periods
      { project-id: project-id, period: period }
      {
        total-revenue: amount,
        distributed: false,
        distribution-timestamp: u0
      }
    )
    (ok true)
  )
)

;; Calculate and allocate revenue shares to investors
(define-public (distribute-revenue (project-id uint) (period uint))
  (let
    ((period-data (map-get? revenue-periods { project-id: project-id, period: period })))

    (asserts! (is-some period-data) (err u404)) ;; Period not found
    (asserts! (not (get distributed (default-to { distributed: false } period-data))) (err u2)) ;; Already distributed
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403)) ;; Only owner can distribute

    ;; Mark as distributed
    (map-set revenue-periods
      { project-id: project-id, period: period }
      (merge (default-to
        {
          total-revenue: u0,
          distributed: false,
          distribution-timestamp: u0
        }
        period-data)
        {
          distributed: true,
          distribution-timestamp: block-height
        }
      )
    )

    (ok true)
  )
)

;; Calculate investor share (to be called by distribute-revenue)
;; This would normally call the investment contract to get ownership percentages
;; For simplicity, we're implementing a basic version
(define-read-only (calculate-investor-share (project-id uint) (period uint) (investor principal))
  (let
    ((period-data (map-get? revenue-periods { project-id: project-id, period: period }))
     (ownership-basis-points u1000)) ;; Placeholder - would normally call investment contract

    (if (is-some period-data)
      (/ (* (get total-revenue (default-to { total-revenue: u0 } period-data)) ownership-basis-points) u10000)
      u0)
  )
)

;; Claim revenue for a period
(define-public (claim-revenue (project-id uint) (period uint))
  (let
    ((period-data (map-get? revenue-periods { project-id: project-id, period: period }))
     (claim-data (map-get? investor-claims { project-id: project-id, period: period, investor: tx-sender }))
     (share (calculate-investor-share project-id period tx-sender)))

    (asserts! (is-some period-data) (err u404)) ;; Period not found
    (asserts! (get distributed (default-to { distributed: false } period-data)) (err u2)) ;; Not yet distributed

    ;; If no existing claim, create one
    (if (is-none claim-data)
      (map-set investor-claims
        { project-id: project-id, period: period, investor: tx-sender }
        { amount: share, claimed: true }
      )
      (begin
        (asserts! (not (get claimed (default-to { claimed: false } claim-data))) (err u3)) ;; Already claimed
        (map-set investor-claims
          { project-id: project-id, period: period, investor: tx-sender }
          { amount: share, claimed: true }
        )
      )
    )

    (ok share)
  )
)

;; Get revenue period data
(define-read-only (get-revenue-period (project-id uint) (period uint))
  (map-get? revenue-periods { project-id: project-id, period: period })
)

;; Get investor claim data
(define-read-only (get-investor-claim (project-id uint) (period uint) (investor principal))
  (map-get? investor-claims { project-id: project-id, period: period, investor: investor })
)
