(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_WILL_NOT_FOUND (err u101))
(define-constant ERR_WILL_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_BENEFICIARY (err u103))
(define-constant ERR_INSUFFICIENT_FUNDS (err u104))
(define-constant ERR_WILL_NOT_READY (err u105))
(define-constant ERR_ALREADY_EXECUTED (err u106))
(define-constant ERR_TESTATOR_STILL_ALIVE (err u107))
(define-constant ERR_INVALID_AMOUNT (err u108))
(define-constant ERR_HEARTBEAT_TOO_RECENT (err u109))

(define-data-var next-will-id uint u1)

(define-map wills
  { will-id: uint }
  {
    testator: principal,
    total-amount: uint,
    created-at: uint,
    last-heartbeat: uint,
    heartbeat-interval: uint,
    executed: bool,
    beneficiary-count: uint
  }
)

(define-map beneficiaries
  { will-id: uint, beneficiary: principal }
  {
    percentage: uint,
    amount: uint,
    claimed: bool
  }
)

(define-map testator-wills
  { testator: principal }
  { will-id: uint }
)

(define-public (create-will (heartbeat-interval uint))
  (let
    (
      (will-id (var-get next-will-id))
      (current-block stacks-block-height)
    )
    (asserts! (> heartbeat-interval u0) ERR_INVALID_AMOUNT)
    (asserts! (is-none (map-get? testator-wills { testator: tx-sender })) ERR_WILL_ALREADY_EXISTS)
    
    (map-set wills
      { will-id: will-id }
      {
        testator: tx-sender,
        total-amount: u0,
        created-at: current-block,
        last-heartbeat: current-block,
        heartbeat-interval: heartbeat-interval,
        executed: false,
        beneficiary-count: u0
      }
    )
    
    (map-set testator-wills
      { testator: tx-sender }
      { will-id: will-id }
    )
    
    (var-set next-will-id (+ will-id u1))
    (ok will-id)
  )
)

(define-public (add-beneficiary (will-id uint) (beneficiary principal) (percentage uint))
  (let
    (
      (will-data (unwrap! (map-get? wills { will-id: will-id }) ERR_WILL_NOT_FOUND))
    )
    (asserts! (is-eq (get testator will-data) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get executed will-data)) ERR_ALREADY_EXECUTED)
    (asserts! (> percentage u0) ERR_INVALID_AMOUNT)
    (asserts! (<= percentage u100) ERR_INVALID_AMOUNT)
    (asserts! (not (is-eq beneficiary tx-sender)) ERR_INVALID_BENEFICIARY)
    (asserts! (is-none (map-get? beneficiaries { will-id: will-id, beneficiary: beneficiary })) ERR_INVALID_BENEFICIARY)
    
    (map-set beneficiaries
      { will-id: will-id, beneficiary: beneficiary }
      {
        percentage: percentage,
        amount: u0,
        claimed: false
      }
    )
    
    (map-set wills
      { will-id: will-id }
      (merge will-data { beneficiary-count: (+ (get beneficiary-count will-data) u1) })
    )
    
    (ok true)
  )
)

(define-public (deposit-funds (will-id uint) (amount uint))
  (let
    (
      (will-data (unwrap! (map-get? wills { will-id: will-id }) ERR_WILL_NOT_FOUND))
    )
    (asserts! (is-eq (get testator will-data) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get executed will-data)) ERR_ALREADY_EXECUTED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set wills
      { will-id: will-id }
      (merge will-data { total-amount: (+ (get total-amount will-data) amount) })
    )
    
    (ok true)
  )
)

(define-public (send-heartbeat (will-id uint))
  (let
    (
      (will-data (unwrap! (map-get? wills { will-id: will-id }) ERR_WILL_NOT_FOUND))
      (current-block stacks-block-height)
    )
    (asserts! (is-eq (get testator will-data) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get executed will-data)) ERR_ALREADY_EXECUTED)
    (asserts! (>= (- current-block (get last-heartbeat will-data)) u1) ERR_HEARTBEAT_TOO_RECENT)
    
    (map-set wills
      { will-id: will-id }
      (merge will-data { last-heartbeat: current-block })
    )
    
    (ok true)
  )
)

(define-public (execute-will (will-id uint))
  (let
    (
      (will-data (unwrap! (map-get? wills { will-id: will-id }) ERR_WILL_NOT_FOUND))
      (current-block stacks-block-height)
      (time-since-heartbeat (- current-block (get last-heartbeat will-data)))
    )
    (asserts! (not (get executed will-data)) ERR_ALREADY_EXECUTED)
    (asserts! (> (get total-amount will-data) u0) ERR_INSUFFICIENT_FUNDS)
    (asserts! (> (get beneficiary-count will-data) u0) ERR_WILL_NOT_READY)
    (asserts! (>= time-since-heartbeat (get heartbeat-interval will-data)) ERR_TESTATOR_STILL_ALIVE)
    
    (map-set wills
      { will-id: will-id }
      (merge will-data { executed: true })
    )
    
    (ok true)
  )
)

(define-public (claim-inheritance (will-id uint))
  (let
    (
      (will-data (unwrap! (map-get? wills { will-id: will-id }) ERR_WILL_NOT_FOUND))
      (beneficiary-data (unwrap! (map-get? beneficiaries { will-id: will-id, beneficiary: tx-sender }) ERR_INVALID_BENEFICIARY))
      (inheritance-amount (/ (* (get total-amount will-data) (get percentage beneficiary-data)) u100))
    )
    (asserts! (get executed will-data) ERR_WILL_NOT_READY)
    (asserts! (not (get claimed beneficiary-data)) ERR_ALREADY_EXECUTED)
    (asserts! (> inheritance-amount u0) ERR_INSUFFICIENT_FUNDS)
    
    (try! (as-contract (stx-transfer? inheritance-amount tx-sender tx-sender)))
    
    (map-set beneficiaries
      { will-id: will-id, beneficiary: tx-sender }
      (merge beneficiary-data { 
        amount: inheritance-amount,
        claimed: true 
      })
    )
    
    (ok inheritance-amount)
  )
)

(define-public (withdraw-funds (will-id uint) (amount uint))
  (let
    (
      (will-data (unwrap! (map-get? wills { will-id: will-id }) ERR_WILL_NOT_FOUND))
    )
    (asserts! (is-eq (get testator will-data) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get executed will-data)) ERR_ALREADY_EXECUTED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= amount (get total-amount will-data)) ERR_INSUFFICIENT_FUNDS)
    
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    
    (map-set wills
      { will-id: will-id }
      (merge will-data { total-amount: (- (get total-amount will-data) amount) })
    )
    
    (ok true)
  )
)

(define-read-only (get-will (will-id uint))
  (map-get? wills { will-id: will-id })
)

(define-read-only (get-beneficiary (will-id uint) (beneficiary principal))
  (map-get? beneficiaries { will-id: will-id, beneficiary: beneficiary })
)

(define-read-only (get-testator-will (testator principal))
  (map-get? testator-wills { testator: testator })
)

(define-read-only (is-will-executable (will-id uint))
  (match (map-get? wills { will-id: will-id })
    will-data
    (let
      (
        (current-block stacks-block-height)
        (time-since-heartbeat (- current-block (get last-heartbeat will-data)))
      )
      (and
        (not (get executed will-data))
        (> (get total-amount will-data) u0)
        (> (get beneficiary-count will-data) u0)
        (>= time-since-heartbeat (get heartbeat-interval will-data))
      )
    )
    false
  )
)

(define-read-only (get-inheritance-amount (will-id uint) (beneficiary principal))
  (match (map-get? wills { will-id: will-id })
    will-data
    (match (map-get? beneficiaries { will-id: will-id, beneficiary: beneficiary })
      beneficiary-data
      (some (/ (* (get total-amount will-data) (get percentage beneficiary-data)) u100))
      none
    )
    none
  )
)

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender))
)