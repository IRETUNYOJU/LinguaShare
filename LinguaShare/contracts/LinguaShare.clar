;; LinguaShare - Crowdsourced Translation Platform
;; Version: 1.0.6

(define-constant ERR_UNAUTHORIZED (err u1001))
(define-constant ERR_INVALID_TASK (err u1002))
(define-constant ERR_TASK_COMPLETED (err u1003))
(define-constant ERR_INSUFFICIENT_REPUTATION (err u1004))
(define-constant ERR_TRANSFER_FAILED (err u1005))
(define-constant CONTRACT_OWNER tx-sender)

;; Define status types
(define-constant STATUS_OPEN u"open")
(define-constant STATUS_IN_PROGRESS u"in-progress")
(define-constant STATUS_COMPLETED u"completed")

;; Data Maps
(define-map translators principal 
  {
    reputation: uint,
    total-translations: uint,
    stx-earned: uint
  }
)

;; Task type definition
(define-map translation-tasks uint 
  {
    owner: principal,
    content: (string-utf8 1024),
    target-language: (string-utf8 10),
    reward: uint,
    status: (string-utf8 20),
    translator: (optional principal),
    completed-translation: (optional (string-utf8 1024))
  }
)

(define-data-var task-nonce uint u0)

;; Initialize translator
(define-public (register-translator) 
  (ok (map-set translators tx-sender {
    reputation: u100,
    total-translations: u0,
    stx-earned: u0
  }))
)

;; Create new translation task
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
        completed-translation: none
      })
      (var-set task-nonce (+ task-id u1))
      task-id))
  )
)

;; Claim task for translation
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
    
    ;; Update task
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
        total-translations: (+ (get total-translations translator-info) u1),
        stx-earned: (+ (get stx-earned translator-info) (get reward task))
      })
    )
    
    ;; Transfer reward
    (try! (as-contract (stx-transfer? (get reward task) tx-sender (get owner task))))
    (ok true)
  )
)

;; Read-only functions
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