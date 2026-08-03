import Foundation

public struct URLSanitizationResult: Sendable, Equatable {
    public var url: URL
    public var removedQueryItems: [String]
    public var unwrappedRedirects: [URL]

    public init(url: URL, removedQueryItems: [String], unwrappedRedirects: [URL]) {
        self.url = url
        self.removedQueryItems = removedQueryItems
        self.unwrappedRedirects = unwrappedRedirects
    }
}

public struct URLSanitizer: Sendable {
    public static let maximumInputBytes = 64 * 1_024

    /// Parameters that are sufficiently specific to be removed on every host. Generic
    /// names such as `source`, `message_id`, `product_id`, or `checksum` deliberately do
    /// not belong here: they are frequently part of a site's functional contract.
    public static let exactTrackingParameters: Set<String> = Set(
        [
            "_branch_match_id", "_branch_referrer", "_ga", "_gl", "_hsenc", "_hsmi",
            "__hsfp", "__hssc", "__hstc", "__twitter_impression", "dclid", "dm_i", "ef_id",
            "epik", "fb_action_ids", "fb_action_types", "fbclid", "gbraid", "gclid", "gclsrc",
            "guccounter", "guce_referrer", "guce_referrer_sig", "igshid", "irclickid", "li_fat_id",
            "mc_cid", "mc_eid", "mkt_tok", "msclkid", "oly_anon_id", "oly_enc_id", "rb_clickid",
            "s_cid", "soc_src", "soc_trk", "srsltid", "sscid", "ttclid", "twclid", "vero_conv",
            "vero_id", "wbraid", "wickedid", "yclid", "zanpid",
        ].map { $0.lowercased() })

    public static let trackingPrefixes: [String] = [
        "utm_", "pk_", "mtm_", "piwik_", "matomo_", "hsa_", "gad_", "rdt_", "snap_",
        "pin_", "quora_", "taboola_", "outbrain_", "braze_", "klaviyo_",
    ]

    public var additionalParameters: Set<String>
    public var allowedParameters: Set<String>
    public var removeTrackingParameters: Bool
    public var unwrapRedirects: Bool

    public init(
        additionalParameters: Set<String> = [],
        allowedParameters: Set<String> = [],
        removeTrackingParameters: Bool = true,
        unwrapRedirects: Bool = true
    ) {
        self.additionalParameters = Set(additionalParameters.map { $0.lowercased() })
        self.allowedParameters = Set(allowedParameters.map { $0.lowercased() })
        self.removeTrackingParameters = removeTrackingParameters
        self.unwrapRedirects = unwrapRedirects
    }

    public func sanitize(_ input: URL) -> URLSanitizationResult {
        guard input.absoluteString.utf8.count <= Self.maximumInputBytes else {
            return URLSanitizationResult(url: input, removedQueryItems: [], unwrappedRedirects: [])
        }
        let unwrapResult =
            unwrapRedirects ? RedirectUnwrapper().unwrap(input) : RedirectUnwrapResult(url: input, hops: [])
        var url = unwrapResult.url
        var removed: [String] = []

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return URLSanitizationResult(url: url, removedQueryItems: removed, unwrappedRedirects: unwrapResult.hops)
        }

        if removeTrackingParameters, let encodedQuery = components.percentEncodedQuery {
            let siteSpecific = siteSpecificParameters(for: components.host?.lowercased() ?? "")
            let fields = encodedQuery.split(separator: "&", omittingEmptySubsequences: false)
            let retained = fields.filter { field in
                let encodedName =
                    field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                let name = String(encodedName).removingPercentEncoding ?? String(encodedName)
                let key = name.lowercased()
                guard !allowedParameters.contains(key) else { return true }
                let shouldRemove =
                    siteSpecific.contains(key) || Self.exactTrackingParameters.contains(key)
                    || additionalParameters.contains(key)
                    || Self.trackingPrefixes.contains(where: { key.hasPrefix($0) })
                if shouldRemove { removed.append(name) }
                return !shouldRemove
            }
            components.percentEncodedQuery = retained.isEmpty ? nil : retained.joined(separator: "&")
        }

        if !removed.isEmpty, let rebuilt = components.url {
            url = rebuilt
        }

        return URLSanitizationResult(
            url: url,
            removedQueryItems: Array(Set(removed)).sorted(),
            unwrappedRedirects: unwrapResult.hops
        )
    }

    private func siteSpecificParameters(for host: String) -> Set<String> {
        if host == "twitter.com" || host == "x.com" || host.hasSuffix(".twitter.com") || host.hasSuffix(".x.com") {
            return ["s", "t", "ref_src", "ref_url", "cxt", "cn"]
        } else if host == "www.facebook.com" || host == "facebook.com" || host.hasSuffix(".facebook.com") {
            return ["mibextid", "__cft__", "__tn__", "ref", "refid", "hc_ref", "fref"]
        } else if host == "www.tiktok.com" || host == "tiktok.com" || host.hasSuffix(".tiktok.com") {
            return [
                "_r", "checksum", "enter_from", "enter_method", "is_copy_url", "is_from_webapp", "language",
                "refer", "referer_url", "sender_device", "sender_web_id", "share_app_id", "share_author_id",
                "share_iid", "share_item_id", "share_link_id", "share_uid", "source", "timestamp", "tt_from",
            ]
        } else if host == "www.youtube.com" || host == "youtube.com" || host == "youtu.be" {
            return ["si", "feature", "pp", "ab_channel"]
        } else if host == "www.amazon.com" || host.hasPrefix("amazon.") || host.contains(".amazon.") {
            return ["tag", "linkcode", "camp", "creative", "creativeasin", "ascsubtag", "ref", "ref_"]
        } else {
            return []
        }
    }
}
