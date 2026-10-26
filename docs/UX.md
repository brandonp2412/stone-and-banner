# UX flows and constraints

## Navigation

1. Home: Start Local Game (future), Resume (future), Rulebook, Board Preview (Stage 1).
2. Local setup: choose 2–4 names and colour, choose deterministic seed, snake-draft starting Villages/roads, confirm.
3. Turn privacy: show "Pass to [player]" interstitial; reveal hidden Strategy Cards only after explicit hold-to-reveal.
4. Turn: production roll, visible season/demand, two action slots, resources, board and hand. Action sheet previews legality and cost before confirmation.
5. Reaction window: interrupting sheet to eligible other seats, with Offer/Escort/Blockade options, cost and eligible target, Pass option; apply in deterministic seat order. In local pass-and-play, pass screen hides private hand when other player's reaction is requested.
6. Invasion: show approaching Reaver Fleet, committed knights and projected defence; each player may commit reactions, then replay result; never surprise-downgrade silently.
7. Finish: show earned Victory Point sources, saveable seed/action replay, rematch.

## Navigation and accessibility rules

- Material 3 native, one activity, no Compose Nav requirement until nested flows warrant it.
- Board interactions use a stable immutable geometry model and batched drawing. Never put random generation, game legality or file IO in Composables.
- Minimum 48 dp touch targets; labels and non-colour distinctions for green/yellow/blue tracks; support large fonts, TalkBack and reduced motion.
- Reserve geometry and action tray heights to avoid jank when a reaction opens. Keep state restoration and event log independent of presentation.
- Every paid action shows exact resource delta and opposing seat prompt. A declined reaction consumes no resources or tokens.
- Back never exits without a match save prompt; uncommitted actions can be dismissed.
- Stage-1 Board is explicitly labelled a preview. All buttons in Stage 1 have genuine visible effects.
