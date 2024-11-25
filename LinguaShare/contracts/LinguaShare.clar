;; LinguaShare - Crowdsourced Translation Platform
;; Version: 1.1.0

;; Error Constants
(define-constant ERR_UNAUTHORIZED (err u1001))
(define-constant ERR_INVALID_TASK (err u1002))
(define-constant ERR_TASK_COMPLETED (err u1003))
(define-constant ERR_INSUFFICIENT_REPUTATION (err u1004))
(define-constant ERR_TRANSFER_FAILED (err u1005))
(define-constant ERR_REPUTATION_CHANGE_FAILED (err u1006))

;; Reputation Constants
(define-constant MIN_REPUTATION u10)
(define-constant MAX_REPUTATION u1000)
(define-constant BASE_REPUTATION u100)
(define-constant PREMIUM_TASK_THRESHOLD u500)

;; Status Types
(define-constant STATUS_OPEN u"open")
(define-constant STATUS_IN_PROGRESS u"in-progress")
(define-constant STATUS_COMPLETED u"completed")
(define-constant STATUS_VERIFIED u"verified")

;; Contract Owner
(define-constant CONTRACT_OWNER tx-sender)

;; Helper Functions for min/max operations
(define-private (get-min (a uint) (b uint))
    (if (<= a b) a b))

(define-private (get-max (a uint) (b uint))
    (if (>= a b) a b))

;; Translators Map with Reputation Tracking
(define-map translators principal 
  {
    reputation: uint,
    total-translations: uint,
    stx-earned: uint,
    quality-score: uint,
    completed-tasks: uint,
    failed-tasks: uint
  }
)

;; Translation Tasks Map with Reputation Requirements
(define-map translation-tasks uint 
  {
    owner: principal,
    content: (string-utf8 1024),
    target-language: (string-utf8 10),
    reward: uint,
    min-translator-reputation: uint,
    status: (string-utf8 20),
    translator: (optional principal),
    completed-translation: (optional (string-utf8 1024)),
    owner-rating: (optional uint),
    deadline: uint
  }
)

;; Task Nonce Tracking
(define-data-var task-nonce uint u0)

;; Translator Registration with Initial Reputation
(define-public (register-translator)
  (ok (map-set translators tx-sender {
    reputation: BASE_REPUTATION,
    total-translations: u0,
    stx-earned: u0,
    quality-score: u100,
    completed-tasks: u0,
    failed-tasks: u0
  }))
)

;; Create Translation Task with Reputation Requirements
(define-public (create-task 
  (content (string-utf8 1024)) 
  (target-language (string-utf8 10)) 
  (reward uint)
  (deadline uint)
  (min-reputation uint)
)
  (let ((task-id (var-get task-nonce)))
    (try! (stx-transfer? reward tx-sender (as-contract tx-sender)))
    (ok (begin
      (map-set translation-tasks task-id {
        owner: tx-sender,
        content: content,
        target-language: target-language,
        reward: reward,
        min-translator-reputation: min-reputation,
        status: STATUS_OPEN,
        translator: none,
        completed-translation: none,
        owner-rating: none,
        deadline: deadline
      })
      (var-set task-nonce (+ task-id u1))
      task-id))
  )
)

;; Claim Task with Reputation Check
(define-public (claim-task (task-id uint))
  (let (
    (task (unwrap! (map-get? translation-tasks task-id) ERR_INVALID_TASK))
    (translator-info (unwrap! (map-get? translators tx-sender) ERR_UNAUTHORIZED))
  )
    (asserts! (is-eq (get status task) STATUS_OPEN) ERR_TASK_COMPLETED)
    (asserts! (>= (get reputation translator-info) (get min-translator-reputation task)) ERR_INSUFFICIENT_REPUTATION)
    
    (ok (map-set translation-tasks task-id 
      (merge task {
        status: STATUS_IN_PROGRESS,
        translator: (some tx-sender)
      })
    ))
  )
)

;; Submit Translation with Reputation Tracking
(define-public (submit-translation (task-id uint) (translation (string-utf8 1024)))
  (let (
    (task (unwrap! (map-get? translation-tasks task-id) ERR_INVALID_TASK))
    (translator-info (unwrap! (map-get? translators tx-sender) ERR_UNAUTHORIZED))
  )
    (asserts! (is-eq (some tx-sender) (get translator task)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status task) STATUS_IN_PROGRESS) ERR_TASK_COMPLETED)
    
    (map-set translation-tasks task-id 
      (merge task {
        status: STATUS_COMPLETED,
        completed-translation: (some translation)
      })
    )
    
    (map-set translators tx-sender
      (merge translator-info {
        total-translations: (+ (get total-translations translator-info) u1),
        completed-tasks: (+ (get completed-tasks translator-info) u1)
      })
    )
    
    (ok true)
  )
)

;; Rate Translation and Adjust Reputation
(define-public (rate-translation (task-id uint) (rating uint))
  (let (
    (task (unwrap! (map-get? translation-tasks task-id) ERR_INVALID_TASK))
    (task-owner tx-sender)
    (translator (unwrap! (get translator task) ERR_INVALID_TASK))
    (translator-info (unwrap! (map-get? translators translator) ERR_UNAUTHORIZED))
  )
    (asserts! (is-eq task-owner (get owner task)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status task) STATUS_COMPLETED) ERR_TASK_COMPLETED)
    (asserts! (and (>= rating u1) (<= rating u5)) ERR_INVALID_TASK)
    
    ;; Update task rating
    (map-set translation-tasks task-id 
      (merge task {
        owner-rating: (some rating)
      })
    )
    
    ;; Adjust translator reputation based on rating
    (let ((new-reputation 
            (if (>= rating u4)
              ;; Positive rating: increase reputation
              (get-min MAX_REPUTATION 
                (+ (get reputation translator-info) 
                   (* rating u10)))
              ;; Negative rating: decrease reputation
              (get-max MIN_REPUTATION 
                (- (get reputation translator-info) 
                   (* (- u5 rating) u20)))
            )))
      
      (map-set translators translator
        (merge translator-info {
          reputation: new-reputation,
          quality-score: (/ 
            (+ (* (get quality-score translator-info) (get completed-tasks translator-info)) 
               rating) 
            (+ (get completed-tasks translator-info) u1))
        })
      )
    )
    
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-translator-reputation (translator principal))
  (get reputation (map-get? translators translator))
)

(define-read-only (can-access-premium-tasks (translator principal))
  (>= 
    (unwrap! (get-translator-reputation translator) false)
    PREMIUM_TASK_THRESHOLD)
)