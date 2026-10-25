import UIKit
import Foundation

struct IssueMetadata: Codable {
    let id: String
    let title: String
    let subtitle: String
    let date: String
    let year: String
    let pages: Int
    let articles: Int
}

class MainViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
    }

    func setupUI() {
        view.backgroundColor = .white

        let titleLabel = UILabel()
        titleLabel.text = "News Reader"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 24)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let importButton = UIButton(type: .system)
        importButton.setTitle("Import News", for: .normal)
        importButton.backgroundColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0)
        importButton.setTitleColor(.white, for: .normal)
        importButton.layer.cornerRadius = 8
        importButton.translatesAutoresizingMaskIntoConstraints = false
        importButton.addTarget(self, action: #selector(importButtonTapped), for: .touchUpInside)
        view.addSubview(importButton)

        let browseButton = UIButton(type: .system)
        browseButton.setTitle("Browse News", for: .normal)
        browseButton.backgroundColor = UIColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1.0)
        browseButton.setTitleColor(.white, for: .normal)
        browseButton.layer.cornerRadius = 8
        browseButton.translatesAutoresizingMaskIntoConstraints = false
        browseButton.addTarget(self, action: #selector(browseButtonTapped), for: .touchUpInside)
        view.addSubview(browseButton)

        let constraints = [
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 60),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            importButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 40),
            importButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            importButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            importButton.heightAnchor.constraint(equalToConstant: 50),

            browseButton.topAnchor.constraint(equalTo: importButton.bottomAnchor, constant: 20),
            browseButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            browseButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            browseButton.heightAnchor.constraint(equalToConstant: 50)
        ]

        NSLayoutConstraint.activate(constraints)
    }

    @objc func importButtonTapped() {

        let documentPicker = UIDocumentPickerViewController(documentTypes: [kUTTypeZIPArchive as String], inMode: .import)
        documentPicker.delegate = self
        present(documentPicker, animated: true)
    }

    @objc func browseButtonTapped() {
        let browseVC = BrowseViewController()
        navigationController?.pushViewController(browseVC, animated: true)
    }
}

extension MainViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]?) {
        guard let url = urls?.first else { return }

        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let targetPath = URL(fileURLWithPath: documentsPath).appendingPathComponent("NewsFiles")

        do {
            try FileManager.default.copyItem(at: url, to: targetPath)
            showImportSuccess()
        } catch {
            showImportError(error)
        }
    }

    func showImportSuccess() {
        let alert = UIAlertController(title: "Import Successful", message: "News files imported successfully", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func showImportError(_ error: Error) {
        let alert = UIAlertController(title: "Import Failed", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}