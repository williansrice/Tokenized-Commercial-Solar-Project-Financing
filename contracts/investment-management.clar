;; Investment Management Contract
;; Tracks capital contributions and ownership

(define-data-var contract-owner principal tx-sender)

;; Project investment details
(define-map project-investments
  { project-id: uint }
  {
    total-investment: uint,
    total-tokens: uint,
    token-price: uint,
    funding-target: uint,
    funding-deadline: uint,
    is-active: bool
  }
)

;; Investor holdings for each project
(define-map investor-holdings
  { project-id: uint, investor: principal }
  { tokens: uint }
)

;; Initialize a new project for investment
(define-public (initialize-project
    (project-id uint)
    (token-price uint)
    (funding-target uint)
    (funding-deadline uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403)) ;; Only owner can initialize
    (asserts! (is-none (map-get? project-investments { project-id: project-id })) (err u1)) ;; Project already exists

    (map-set project-investments
      { project-id: project-id }
      {
        total-investment: u0,
        total-tokens: u0,
        token-price: token-price,
        funding-target: funding-target,
        funding-deadline: funding-deadline,
        is-active: true
      }
    )
    (ok true)
  )
)

;; Invest in a project
(define-public (invest (project-id uint) (amount uint))
  (let
    ((project (map-get? project-investments { project-id: project-id })))

    (asserts! (is-some project) (err u404)) ;; Project not found
    (asserts! (get is-active (default-to { is-active: false } project)) (err u2)) ;; Project not active
    (asserts! (< block-height (get funding-deadline (default-to { funding-deadline: u0 } project))) (err u3)) ;; Funding deadline passed

    (let
      ((token-price (get token-price (default-to { token-price: u1 } project)))
       (tokens-to-mint (/ amount token-price)))

      ;; Update project investment totals
      (map-set project-investments
        { project-id: project-id }
        (merge (default-to
          {
            total-investment: u0,
            total-tokens: u0,
            token-price: u1,
            funding-target: u0,
            funding-deadline: u0,
            is-active: false
          }
          project)
          {
            total-investment: (+ (get total-investment (default-to { total-investment: u0 } project)) amount),
            total-tokens: (+ (get total-tokens (default-to { total-tokens: u0 } project)) tokens-to-mint)
          }
        )
      )

      ;; Update investor holdings
      (let
        ((current-holding (default-to { tokens: u0 }
                          (map-get? investor-holdings { project-id: project-id, investor: tx-sender }))))
        (map-set investor-holdings
          { project-id: project-id, investor: tx-sender }
          { tokens: (+ (get tokens current-holding) tokens-to-mint) }
        )
      )

      (ok tokens-to-mint)
    )
  )
)

;; Close project funding
(define-public (close-funding (project-id uint))
  (let
    ((project (map-get? project-investments { project-id: project-id })))
    (asserts! (is-some project) (err u404)) ;; Project not found
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err u403)) ;; Only owner can close funding

    (map-set project-investments
      { project-id: project-id }
      (merge (default-to
        {
          total-investment: u0,
          total-tokens: u0,
          token-price: u1,
          funding-target: u0,
          funding-deadline: u0,
          is-active: false
        }
        project)
        { is-active: false }
      )
    )
    (ok true)
  )
)

;; Get project investment details
(define-read-only (get-project-investment (project-id uint))
  (map-get? project-investments { project-id: project-id })
)

;; Get investor holdings for a project
(define-read-only (get-investor-holding (project-id uint) (investor principal))
  (map-get? investor-holdings { project-id: project-id, investor: investor })
)

;; Calculate ownership percentage (returns basis points, e.g. 1000 = 10%)
(define-read-only (get-ownership-percentage (project-id uint) (investor principal))
  (let
    ((project (map-get? project-investments { project-id: project-id }))
     (holding (map-get? investor-holdings { project-id: project-id, investor: investor })))
    (if (and (is-some project) (is-some holding))
      (let
        ((investor-tokens (get tokens (default-to { tokens: u0 } holding)))
         (total-tokens (get total-tokens (default-to { total-tokens: u1 } project))))
        (if (> total-tokens u0)
          (/ (* investor-tokens u10000) total-tokens)
          u0))
      u0)
  )
)
