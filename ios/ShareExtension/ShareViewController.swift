import UIKit
import MobileCoreServices

// Genel amaçlı Share Extension.
//
// Başka bir uygulamadan (Instagram, Safari, YouTube, Notlar...) paylaşılan
// bağlantıyı veya metni alır, kullanıcıya isteğe bağlı not yazdırır ve
// App Group kuyruğuna yazar. Ana uygulama açılınca Flutter tarafı
// (lib/services/share_service.dart) kuyruğu okuyup işler.
//
// Uygulamaya özel davranış (ör. sadece Instagram linki kabul etmek)
// gerekiyorsa `acceptsPlainText` ve `extractUrl` fonksiyonunu düzenle.

// MARK: - Yerelleştirme (cihaz dilini otomatik algılar)
private enum L {
    static let lang: String = {
        let preferred = Locale.preferredLanguages.first ?? "en"
        let code = String(preferred.prefix(2)).lowercased()
        return ["tr", "en", "pt", "es"].contains(code) ? code : "en"
    }()

    private static let strings: [String: [String: String]] = [
        "searching": [
            "tr": "İçerik aranıyor...", "en": "Looking for content...",
            "pt": "Procurando conteúdo...", "es": "Buscando contenido...",
        ],
        "ready": [
            "tr": "Hazır. İstersen not ekleyip kaydet.",
            "en": "Ready. Add a note if you like, then save.",
            "pt": "Pronto. Adicione uma nota se quiser e salve.",
            "es": "Listo. Agrega una nota si quieres y guarda.",
        ],
        "not_found": [
            "tr": "Paylaşılan içerikte bağlantı veya metin bulunamadı.",
            "en": "No link or text found in the shared content.",
            "pt": "Nenhum link ou texto encontrado no conteúdo compartilhado.",
            "es": "No se encontró enlace ni texto en el contenido compartido.",
        ],
        "note_placeholder": [
            "tr": "Not (isteğe bağlı)", "en": "Note (optional)",
            "pt": "Nota (opcional)", "es": "Nota (opcional)",
        ],
        "save": ["tr": "Kaydet", "en": "Save", "pt": "Salvar", "es": "Guardar"],
        "cancel": ["tr": "Vazgeç", "en": "Cancel", "pt": "Cancelar", "es": "Cancelar"],
        "saved": [
            "tr": "Kaydedildi. Uygulamayı açınca işlenecek.",
            "en": "Saved. It will be processed when you open the app.",
            "pt": "Salvo. Será processado quando você abrir o app.",
            "es": "Guardado. Se procesará al abrir la app.",
        ],
        "error": [
            "tr": "Kaydetme sırasında hata oluştu. Tekrar dene.",
            "en": "Something went wrong. Try again.",
            "pt": "Algo deu errado. Tente novamente.",
            "es": "Algo salió mal. Inténtalo de nuevo.",
        ],
    ]

    static func t(_ key: String) -> String {
        return strings[key]?[lang] ?? strings[key]?["en"] ?? key
    }
}

class ShareViewController: UIViewController {

    // tool/rename.dart bu değeri yeni bundle ID'ye göre günceller.
    private let appGroupId = "group.com.example.starter"
    private let sharedQueueKey = "shared_payload_queue"

    /// true: bağlantı yoksa düz metni de kabul et. false: sadece bağlantı.
    private let acceptsPlainText = true

    private var hasCompletedRequest = false
    private var extractedUrl: String?
    private var extractedText: String?

    private let supportedTypeIdentifiers: [String] = [
        kUTTypeURL as String,
        "public.url",
        kUTTypeText as String,
        kUTTypePlainText as String,
        "public.text",
        "public.plain-text",
    ]

    private var appDisplayName: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? ""
    }

    // MARK: UI

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.keyboardDismissMode = .interactive
        return view
    }()

    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        return label
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = L.t("searching")
        label.font = .systemFont(ofSize: 15, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }()

    private let previewLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .tertiaryLabel
        label.numberOfLines = 3
        label.textAlignment = .center
        return label
    }()

    private let noteTextView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .systemFont(ofSize: 15, weight: .regular)
        textView.layer.cornerRadius = 10
        textView.layer.borderWidth = 1
        textView.accessibilityLabel = L.t("note_placeholder")
        return textView
    }()

    private let saveButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(L.t("save"), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        // Marka rengini burada değiştir.
        button.backgroundColor = UIColor(red: 1.0, green: 0.42, blue: 0.21, alpha: 1.0)
        button.tintColor = .white
        button.layer.cornerRadius = 12
        button.isEnabled = false
        button.alpha = 0.55
        return button
    }()

    private let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(L.t("cancel"), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        return button
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        registerKeyboardObservers()
        startExtraction()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        noteTextView.layer.borderColor = UIColor.separator.cgColor
        titleLabel.text = appDisplayName

        let noteLabel = UILabel()
        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        noteLabel.text = L.t("note_placeholder")
        noteLabel.font = .systemFont(ofSize: 14, weight: .semibold)

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            messageLabel,
            activityIndicator,
            previewLabel,
            noteLabel,
            noteTextView,
            saveButton,
            cancelButton,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill

        saveButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        noteTextView.heightAnchor.constraint(equalToConstant: 90).isActive = true

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
        ])

        saveButton.addTarget(self, action: #selector(onTapSave), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(onTapCancel), for: .touchUpInside)
        activityIndicator.startAnimating()
    }

    private func registerKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardFrame(notification:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardFrame(notification:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func handleKeyboardFrame(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let convertedKeyboardFrame = view.convert(keyboardFrame, from: nil)
        let overlap = max(0, view.bounds.maxY - convertedKeyboardFrame.minY)
        let bottomInset = overlap > 0 ? overlap - view.safeAreaInsets.bottom + 12 : 0

        scrollView.contentInset.bottom = bottomInset
        scrollView.verticalScrollIndicatorInsets.bottom = bottomInset

        if overlap > 0 {
            let targetRect = noteTextView.convert(noteTextView.bounds, to: scrollView)
            scrollView.scrollRectToVisible(targetRect.insetBy(dx: 0, dy: -16), animated: true)
        }
    }

    // MARK: İçerik çıkarma

    private func startExtraction() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            setNotFoundState()
            return
        }

        var loadedAnything = false

        for item in extensionItems {
            if let inlineText = item.attributedContentText?.string {
                consume(inlineText)
            }

            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                let preferredTypes = supportedTypeIdentifiers.filter {
                    provider.hasItemConformingToTypeIdentifier($0)
                }
                for typeIdentifier in preferredTypes {
                    loadedAnything = true
                    provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] (data, _) in
                        DispatchQueue.main.async {
                            self?.consume(data)
                        }
                    }
                }
            }
        }

        if !loadedAnything {
            finishExtraction()
            return
        }

        // Sağlayıcılar asenkron döner; kısa bir süre bekleyip sonucu değerlendir.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.finishExtraction()
        }
    }

    private func consume(_ payload: Any?) {
        if hasCompletedRequest { return }
        guard let text = stringValue(of: payload) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }

        if extractedUrl == nil, let url = extractUrl(from: trimmed) {
            extractedUrl = url
        }
        // URL dışında anlamlı metin varsa en uzun olanı sakla (ör. caption).
        if !isUrlOnly(trimmed), trimmed.count > (extractedText?.count ?? 0) {
            extractedText = trimmed
        }
        if extractedUrl != nil {
            setReadyState()
        }
    }

    private func finishExtraction() {
        if hasCompletedRequest { return }
        if extractedUrl != nil || (acceptsPlainText && extractedText != nil) {
            setReadyState()
        } else {
            setNotFoundState()
        }
    }

    private func stringValue(of payload: Any?) -> String? {
        if let url = payload as? URL { return url.absoluteString }
        if let text = payload as? String { return text }
        if let attributed = payload as? NSAttributedString { return attributed.string }
        if let data = payload as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }

    private func extractUrl(from text: String) -> String? {
        let pattern = #"https?://[^\s<>"]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              let range = Range(match.range(at: 0), in: text) else {
            return nil
        }
        return String(text[range])
            .replacingOccurrences(of: #"[\]\)\}\.,!?]+$"#, with: "", options: .regularExpression)
    }

    private func isUrlOnly(_ text: String) -> Bool {
        return text.range(of: #"^https?://\S+$"#, options: .regularExpression) != nil
    }

    private func setReadyState() {
        activityIndicator.stopAnimating()
        messageLabel.text = L.t("ready")
        previewLabel.text = extractedUrl ?? extractedText
        saveButton.isEnabled = true
        saveButton.alpha = 1.0
    }

    private func setNotFoundState() {
        activityIndicator.stopAnimating()
        messageLabel.text = L.t("not_found")
        saveButton.isEnabled = false
        saveButton.alpha = 0.55
    }

    // MARK: Kaydet / Vazgeç

    @objc private func onTapSave() {
        guard extractedUrl != nil || extractedText != nil else {
            setNotFoundState()
            return
        }
        guard let userDefaults = UserDefaults(suiteName: appGroupId) else {
            messageLabel.text = L.t("error")
            return
        }

        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "url": extractedUrl ?? "",
            "text": extractedText ?? "",
            "note": noteTextView.text.trimmingCharacters(in: .whitespacesAndNewlines),
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]

        var queue = userDefaults.array(forKey: sharedQueueKey) as? [[String: Any]] ?? []
        queue.append(payload)
        userDefaults.set(queue, forKey: sharedQueueKey)
        userDefaults.synchronize()

        messageLabel.text = L.t("saved")
        saveButton.isEnabled = false
        saveButton.alpha = 0.55
        completeRequest(after: 0.4)
    }

    @objc private func onTapCancel() {
        completeRequest(after: 0.0)
    }

    private func completeRequest(after delay: TimeInterval) {
        if hasCompletedRequest { return }
        hasCompletedRequest = true

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}
