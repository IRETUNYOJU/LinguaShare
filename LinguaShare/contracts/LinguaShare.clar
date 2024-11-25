;; LinguaShare - Crowdsourced Translation Platform
;; Version: 1.0.8

;; Error Constants
(define-constant ERR_UNAUTHORIZED (err u1001))
(define-constant ERR_INVALID_TASK (err u1002))
(define-constant ERR_TASK_COMPLETED (err u1003))
(define-constant ERR_INSUFFICIENT_REPUTATION (err u1004))
(define-constant ERR_TRANSFER_FAILED (err u1005))
(define-constant ERR_ORACLE_VERIFICATION_FAILED (err u1006))

;; Contract Owner
(define-constant CONTRACT_OWNER tx-sender)

;; Status Types
(define-constant STATUS_OPEN u"open")
(define-constant STATUS_IN_PROGRESS u"in-progress")
(define-constant STATUS_COMPLETED u"completed")
(define-constant STATUS_VERIFIED u"verified")

;; Oracle Address (for task verification)
(define-constant ORACLE_ADDRESS (as-contract tx-sender))

;; Data Maps
(define-map translators principal 
  {
    reputation: uint,
    total-translations: uint,
    stx-earned: uint,
    verification-success-rate: uint
  }
)

;; Translation Tasks Map
(define-map translation-tasks uint 
  {
    owner: principal,
    content: (string-utf8 1024),
    target-language: (string-utf8 10),
    reward: uint,
    status: (string-utf8 20),
    translator: (optional principal),
    completed-translation: (optional (string-utf8 1024)),
    verification-status: (optional bool),
    verifier: (optional principal)
  }
)

;; Nonce for task tracking
(define-data-var task-nonce uint u0)

;; Initialize translator with base reputation
(define-public (register-translator) 
  (ok (map-set translators tx-sender {
    reputation: u100,
    total-translations: u0,
    stx-earned: u0,
    verification-success-rate: u100
  }))
)

;; Create new translation task with reward
(define-public (create-task (content (string-utf8 1024)) (target-language (string-utf8 10)) (reward uint))
  (let 
    ((task-id (var-get task-nonce)))
    (try! (stx-transfer? reward tx-sender (as-contract tx-sender)))
    (ok (begin
      (map-set translation-tasks task-id {
        owner: tx-sender,
        content: content,
        target-language: target-language,
        reward: reward,
        status: STATUS_OPEN,
        translator: none,
        completed-translation: none,
        verification-status: none,
        verifier: none
      })
      (var-set task-nonce (+ task-id u1))
      task-id))
  )
)

;; Claim task for translation with reputation check
(define-public (claim-task (task-id uint))
  (let (
    (task (unwrap! (map-get? translation-tasks task-id) ERR_INVALID_TASK))
    (translator-info (unwrap! (map-get? translators tx-sender) ERR_UNAUTHORIZED))
  )
    (asserts! (is-eq (get status task) STATUS_OPEN) ERR_TASK_COMPLETED)
    (asserts! (>= (get reputation translator-info) u50) ERR_INSUFFICIENT_REPUTATION)
    
    (ok (map-set translation-tasks task-id 
      (merge task {
        status: STATUS_IN_PROGRESS,
        translator: (some tx-sender)
      })
    ))
  )
)

;; Submit completed translation
(define-public (submit-translation (task-id uint) (translation (string-utf8 1024)))
  (let (
    (task (unwrap! (map-get? translation-tasks task-id) ERR_INVALID_TASK))
    (translator-info (unwrap! (map-get? translators tx-sender) ERR_UNAUTHORIZED))
  )
    (asserts! (is-eq (some tx-sender) (get translator task)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status task) STATUS_IN_PROGRESS) ERR_TASK_COMPLETED)
    
    ;; Update task with submitted translation
    (map-set translation-tasks task-id 
      (merge task {
        status: STATUS_COMPLETED,
        completed-translation: (some translation)
      })
    )
    
    ;; Update translator stats
    (map-set translators tx-sender
      (merge translator-info {
        reputation: (+ (get reputation translator-info) u10),
        total-translations: (+ (get total-translations translator-info) u1)
      })
    )
    
    (ok true)
  )
)

;; Oracle-based translation verification
(define-public (verify-translation (task-id uint) (is-accurate bool))
  (let (
    (task (unwrap! (map-get? translation-tasks task-id) ERR_INVALID_TASK))
    (translator-info (unwrap! (map-get? translators 
      (unwrap! (get translator task) ERR_INVALID_TASK)) ERR_UNAUTHORIZED))
  )
    ;; Only contract can verify
    (asserts! (is-eq tx-sender (as-contract tx-sender)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status task) STATUS_COMPLETED) ERR_TASK_COMPLETED)
    
    ;; Update task with verification
    (map-set translation-tasks task-id 
      (merge task {
        status: STATUS_VERIFIED,
        verification-status: (some is-accurate),
        verifier: (some tx-sender)
      })
    )
    
    ;; Update translator reputation based on verification
    (if is-accurate 
      ;; Successful verification
      (begin 
        (map-set translators 
          (unwrap! (get translator task) ERR_INVALID_TASK)
          (merge translator-info {
            reputation: (+ (get reputation translator-info) u20),
            verification-success-rate: (+ (get verification-success-rate translator-info) u1)
          })
        )
        ;; Transfer reward if verified
        (try! (as-contract (stx-transfer? (get reward task) tx-sender (unwrap! (get translator task) ERR_INVALID_TASK))))
      )
      ;; Failed verification
      (map-set translators 
        (unwrap! (get translator task) ERR_INVALID_TASK)
        (merge translator-info {
          reputation: (- (get reputation translator-info) u10)
        })
      )
    )
    
    (ok true)
  )
)

;; Read-only functions for task and translator information
(define-read-only (get-task (task-id uint))
  (map-get? translation-tasks task-id)
)

(define-read-only (get-translator-info (translator principal))
  (map-get? translators translator)
)

;; Contract status check
(define-read-only (get-contract-info)
  {
    tasks: (var-get task-nonce),
    owner: CONTRACT_OWNER
  }
)