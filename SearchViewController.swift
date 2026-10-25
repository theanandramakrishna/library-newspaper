import UIKit

class SearchViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        setupSearchUI()
    }

    func setupSearchUI() {
        title = "Search"
        view.backgroundColor = .white

        let searchBar = UISearchBar(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 44))
        searchBar.delegate = self
        searchBar.placeholder = "Search articles..."
        view.addSubview(searchBar)

        let tableView = UITableView(frame: CGRect(x: 0, y: 44, width: view.bounds.width, height: view.bounds.height - 44))
        tableView.dataSource = self
        tableView.delegate = self
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SearchResultCell")
        view.addSubview(tableView)
    }

    var searchResults: [SearchResult] = []

    func performSearch(_ query: String) {
        searchResults.removeAll()

        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let newsPath = URL(fileURLWithPath: documentsPath).appendingPathComponent("NewsFiles")

        guard FileManager.default.fileExists(atPath: newsPath.path) else {
            return
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: newsPath.path)
            for directory in contents {
                let issuePath = newsPath.appendingPathComponent(directory)
                let pagesPath = issuePath.appendingPathComponent("pages")
                let articlesPath = issuePath.appendingPathComponent("articles")

                if let pageFiles = try? FileManager.default.contentsOfDirectory(atPath: pagesPath.path) {
                    for pageFile in pageFiles {
                        if pageFile.hasSuffix(".jpg") || pageFile.hasSuffix(".jpeg") {
                            let pagePath = pagesPath.appendingPathComponent(pageFile)
                            let pageNumber = extractPageNumber(from: pageFile)

                            let ocrPath = issuePath.appendingPathComponent("ocr").appendingPathComponent("page_\(pageNumber).txt")
                            if let ocrData = try? Data(contentsOf: ocrPath), let ocrText = String(data: ocrData, encoding: .utf8) {
                                if ocrText.range(of: query, options: .caseInsensitive) != nil {
                                    let result = SearchResult(
                                        issueId: directory,
                                        pageNumber: pageNumber,
                                        headline: "Page \(pageNumber)",
                                        snippet: extractSnippet(from: ocrText, query: query)
                                    )
                                    searchResults.append(result)
                                }
                            }
                        }
                    }
                }
            }

            (view.subviews.last as? UITableView)?.reloadData()
        } catch {
            print("Error performing search: \(error)")
        }
    }

    func extractPageNumber(from fileName: String) -> Int {
        let components = fileName.components(separatedBy: ".")
        if components.first?.hasPrefix("page_") == true {
            let numberString = String(components.first?.dropFirst(5) ?? "0")
            return Int(numberString) ?? 0
        }
        return 0
    }

    func extractSnippet(from text: String, query: String) -> String {
        let range = text.range(of: query, options: .caseInsensitive) ?? text.startIndex
        let startIndex = range
        let endIndex = text.index(startIndex, offsetBy: min(100, text.distance(from: startIndex, to: text.endIndex)))
        let snippet = String(text[startIndex..<endIndex])
        return snippet + "..."
    }

    func navigateToIssue(_ result: SearchResult) {
        let pageViewController = PageViewController(issueId: result.issueId)
        navigationController?.pushViewController(pageViewController, animated: true)
    }
}

extension SearchViewController: UISearchBarDelegate {

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        performSearch(searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

extension SearchViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResults.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
        let result = searchResults[indexPath.row]

        var text = "Page \(result.pageNumber)\n"
        text.append(result.headline)
        text.append("\n")
        text.append(result.snippet)

        cell.textLabel?.text = text

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let result = searchResults[indexPath.row]
        navigateToIssue(result)
    }
}

struct SearchResult {
    let issueId: String
    let pageNumber: Int
    let headline: String
    let snippet: String
}