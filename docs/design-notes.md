# Design notes (draft)

## Decisions
1. **Regulator is admin of all roles.** Only the Regulator grants Manufacturer, Distributor, Pharmacy and Oracle accounts.
2. **Module wiring is one-time.** `BatchRegistry.setModules()` can be called once, so no one can swap the monitor or compliance contract later.
3. **Recall beats compromise.** A recalled batch can never go back to `Compromised`. Both freeze custody.
4. **Consumer check is a view call.** `verifyForConsumer()` costs no gas and needs no wallet.
5. **"Safe" means:** approved, not compromised, not recalled, not expired.

## Open questions (to settle before Nov 15)
- Should readings be batched (many readings, one tx) to cut gas?
- Should the Oracle be one wallet or a set of sensor wallets?
- Should the Regulator be able to un-flag a false `Compromised` after review?
- Do we need `Rejected` status when a recipient declines a shipment?

## Known limits of the draft
- Physical-to-digital link (a fake QR on a fake box) is out of scope; the sensor is trusted via the Oracle role.
- Tests cover one happy path and a few rules only. Full suite and gas report come later.
