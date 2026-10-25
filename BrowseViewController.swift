import UIKit
import Foundation

class BrowseViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        setupBrowseUI()
        loadNewsFiles()
    }

    func setupBrowseUI() {
        title = "Browse News"
        view.backgroundColor = .white

        let tableView = UITableView(frame: view.bounds, style: .grouped)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "IssueCell")
        view.addSubview(tableView)
    }

    var issues: [IssueMetadata] = []

    func loadNewsFiles() {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let newsPath = URL(fileURLWithPath: documentsPath).appendingPathComponent("NewsFiles")

        guard FileManager.default.fileExists(atPath: newsPath.path) else {
            showNoNewsMessage()
            return
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: newsPath.path)
            for directory in contents {
                let issuePath = newsPath.appendingPathComponent(directory)
                let metadataPath = issuePath.appendingPathComponent("metadata.json")

                if FileManager.default.fileExists(atPath: metadataPath.path) {
                    if let data = try? Data(contentsOf: metadataPath), let issue = parseIssue(data: data) {
                        issues.append(issue)
                    }
                }
            }

            (view.subviews.first as? UITableView)?.reloadData()
        } catch {
            print("Error loading news files: \(error)")
            showErrorMessage("Failed to load news files")
        }
    }

    func showNoNewsMessage() {
        let label = UILabel()
        label.text = "No news files found. Import news files first."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    func showErrorMessage(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func parseIssue(data: Data) -> IssueMetadata? {
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(IssueMetadata.self, from: data)
        } catch {
            print("Error parsing issue: \(error)")
            return nil
        }
    }
}

extension BrowseViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return issues.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "IssueCell", for: indexPath)
        let issue = issues[indexPath.row]

        var text = issue.title
        text.append("\n")
        text.append(issue.subtitle)
        text.append("\n")
        text.append(issue.date)
        text.append(" \(issue.year)")

        cell.textLabel?.text = text
        cell.detailTextLabel?.text = "\(issue.pages) pages, \(issue.articles) articles"

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let issue = issues[indexPath.row]
        let pageViewController = PageViewController(issueId: issue.id)
        navigationController?.pushViewController(pageViewController, animated: true)
    }
}