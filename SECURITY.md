# Security and Privacy Notes

## Local-first behavior

Rules, settings, link history, and diagnostics are stored locally under `~/Library/Application Support/PowerTools`. The app does not include analytics, telemetry, an account system, cloud synchronization, or uploads.

Network access is used only for enabled short-link expansion. Power Tools contacts only its built-in shortener host list with an ephemeral URLSession. It stops automatic redirects itself: another built-in shortener may be contacted, but the arbitrary final destination is returned to the selected browser without Power Tools fetching it. Custom and unknown redirect-service resolution are intentionally unsupported because a DNS preflight cannot safely pin an arbitrary URLSession connection.

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
- The JavaScriptCore wrapper exposes only serialized URL/source objects and does not inject native objects.
- Transforms run in a separate helper process with a one-second deadline, a 64 KB script limit, bounded output, and HTTP/HTTPS-only results. A hung or crashed transform is skipped without blocking the host app.

## Redirect resolution

Before each request, the resolver verifies that the URL is still a built-in shortener and rejects localhost, link-local, private, reserved, or otherwise non-public destinations. URLSession automatic redirects are disabled. Redirect headers are parsed by Power Tools, and it makes another request only when the next host is also built in; the final arbitrary destination is never prefetched. This makes the network boundary independent of a preflight DNS result for attacker-selected hosts and closes the previous DNS-rebinding/SSRF gap.

## History and diagnostics

History and verbose logs may contain sensitive URLs, including path and query values that are not classified as tracking data. Users can disable history, disable logging, and clear both stores from the UI. History uses a bounded 16 MB append journal, is flushed on termination, and compacts automatically; an unreadable file is preserved and write-protected until the user explicitly backs it up and resets it.

A future “private domain” list should suppress history/logging for selected hosts before this becomes a broadly distributed product.

## Custom applications and schemes

Rules may launch arbitrary selected applications. JavaScript transforms are restricted to HTTP and HTTPS results. This is intentional local automation, but imported settings should still not be trusted without inspection.
