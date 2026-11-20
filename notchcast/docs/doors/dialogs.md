# Door: Dialogs

**Dialogs** go through `context.confirm(title, message, confirmTitle)`, Notchcast's own yes/no dialog (`AppCore.confirm`, neutral tone), or `context.confirmDestructive` with the same arguments when the step loses something (danger tone, destructive button), never `NSAlert`; `NotchcastCore` sets both on every context, and both are nil in harnesses, which set their own (`guard let confirm = context.confirmDestructive, await confirm(…)`).
