# Security and Privacy Notes

## Local-first behavior

Rules, settings, link history, and diagnostics are stored locally under `~/Library/Application Support/PowerTools`. The app does not include analytics, telemetry, an account system, cloud synchronization, or uploads.

Network access is used only for enabled short-link expansion. Recognized shorteners are resolved with an ephemeral URLSession. Resolving arbitrary unknown redirect services is off by default.

## Sandbox model

The host application is a direct-distribution, non-sandboxed utility so it can inspect browser profile and PWA metadata under the user's Application Support and Applications directories. Browser applications themselves are discovered through the system's registered URL handlers rather than by sweeping every installed application bundle. The Safari and Share extensions are sandboxed.

This is a deliberate tradeoff for the broader Power Tools host. A store build should use a separate configuration with security-scoped user-selected folders and should not inherit this entitlement model without review.

## Sensitive permissions

The Link Router host does not request Accessibility, Automation, Full Disk Access, Screen Recording, or Input Monitoring. Safari private-window routing is intentionally unavailable because Safari does not expose that behavior without privileged UI automation. Private-window routing remains available for Chromium- and Firefox-family browsers through their supported launch arguments.

Automatic clipboard cleaning is optional and disabled by default. On current macOS releases, enabling it may cause the system to request pasteboard access when the first copied web URL is inspected. User-invoked clipboard commands remain available without background monitoring.

## JavaScript transforms

Rule imports may contain JavaScript. Treat a rule file as executable configuration:

- Review scripts before importing files from another person.
- Do not import a rule merely because it is JSON.
- The current JavaScriptCore wrapper exposes only the serialized URL/source objects and does not inject native objects.
- A non-terminating script can still block the routing operation. A public hardened release should execute transforms in a helper process with an enforced deadline.

## Redirect resolution

The resolver rejects obvious localhost, link-local, and RFC1918 literal hosts. Unknown-host resolution remains disabled by default. A production security review should additionally enforce redirect checks before every hop and guard against DNS rebinding if this feature is exposed to managed-enterprise environments.

## History and diagnostics

History and verbose logs may contain sensitive URLs, including path and query values that are not classified as tracking data. Users can disable history, disable logging, and clear both stores from the UI.

A future “private domain” list should suppress history/logging for selected hosts before this becomes a broadly distributed product.

## Custom applications and schemes

Rules may launch arbitrary selected applications and JavaScript transforms may produce arbitrary registered URL schemes. This is intentional local automation. Imported settings should not be trusted without inspection.
