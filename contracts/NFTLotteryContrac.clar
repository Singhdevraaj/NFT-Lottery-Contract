;; NFT Lottery Contract
;; A lottery system where participants can enter and winners receive random NFTs

;; Define the NFT
(define-non-fungible-token lottery-nft uint)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-lottery-not-active (err u101))
(define-constant err-insufficient-payment (err u102))
(define-constant err-already-entered (err u103))
(define-constant err-no-participants (err u104))
(define-constant err-invalid-amount (err u105))

;; Data variables
(define-data-var lottery-active bool false)
(define-data-var entry-fee uint u1000000) ;; 1 STX in microSTX
(define-data-var lottery-round uint u0)
(define-data-var total-nfts-minted uint u0)

;; Maps
(define-map participants uint (list 100 principal))
(define-map user-entries {user: principal, round: uint} bool)

;; Function 1: Enter Lottery
;; Allows users to enter the current lottery round by paying the entry fee
(define-public (enter-lottery)
  (let (
    (current-round (var-get lottery-round))
    (fee (var-get entry-fee))
    (current-participants (default-to (list) (map-get? participants current-round)))
  )
    (begin
      ;; Check if lottery is active
      (asserts! (var-get lottery-active) err-lottery-not-active)
      
      ;; Check if user hasn't already entered this round
      (asserts! (is-none (map-get? user-entries {user: tx-sender, round: current-round})) err-already-entered)
      
      ;; Transfer entry fee to contract
      (try! (stx-transfer? fee tx-sender (as-contract tx-sender)))
      
      ;; Add participant to the list
      (map-set participants current-round (unwrap-panic (as-max-len? (append current-participants tx-sender) u100)))
      
      ;; Mark user as entered for this round
      (map-set user-entries {user: tx-sender, round: current-round} true)
      
      (ok true)
    )
  )
)

;; Function 2: Draw Winner and Distribute NFT
;; Randomly selects a winner from participants and mints them an NFT
(define-public (draw-winner)
  (let (
    (current-round (var-get lottery-round))
    (current-participants (default-to (list) (map-get? participants current-round)))
    (participant-count (len current-participants))
    (current-nft-id (+ (var-get total-nfts-minted) u1))
  )
    (begin
      ;; Only owner can draw winner
      (asserts! (is-eq tx-sender contract-owner) err-owner-only)
      
      ;; Check if there are participants
      (asserts! (> participant-count u0) err-no-participants)
      
      ;; Generate pseudo-random index using simple hash-based approach
      (let (
        (random-seed (+ current-round participant-count (var-get total-nfts-minted)))
        (winner-index (mod random-seed participant-count))
        (winner (unwrap-panic (element-at current-participants winner-index)))
      )
        ;; Mint NFT to winner
        (try! (nft-mint? lottery-nft current-nft-id winner))
        
        ;; Update total NFTs minted
        (var-set total-nfts-minted current-nft-id)
        
        ;; Increment lottery round and reset for next round
        (var-set lottery-round (+ current-round u1))
        
        ;; Print winner information
        (print {
          event: "lottery-winner",
          winner: winner,
          round: current-round,
          nft-id: current-nft-id
        })
        
        (ok winner)
      )
    )
  )
)

;; Helper Functions (Read-only)

;; Get current lottery info
(define-read-only (get-lottery-info)
  (ok {
    active: (var-get lottery-active),
    entry-fee: (var-get entry-fee),
    current-round: (var-get lottery-round),
    total-nfts-minted: (var-get total-nfts-minted)
  })
)

;; Get participants for a specific round
(define-read-only (get-participants (round uint))
  (ok (map-get? participants round))
)

;; Check if user has entered current round
(define-read-only (has-user-entered (user principal))
  (let (
    (current-round (var-get lottery-round))
  )
    (ok (is-some (map-get? user-entries {user: user, round: current-round})))
  )
)

;; Owner functions

;; Start/Stop lottery
(define-public (toggle-lottery)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set lottery-active (not (var-get lottery-active)))
    (ok (var-get lottery-active))
  )
)

;; Update entry fee
(define-public (set-entry-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> new-fee u0) err-invalid-amount)
    (var-set entry-fee new-fee)
    (ok true)
  )
)
