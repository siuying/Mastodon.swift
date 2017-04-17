import Foundation
import Alamofire
import Moya
import RxSwift
import Gloss

#if COCOAPODS
    import Moya_Gloss
#else
    import RxMoya
    import MoyaGloss
    import RxMoyaGloss
#endif

extension String {
    fileprivate func fetchParameter(_ name: String) -> Int? {
        if let range = range(of: "\(name)=([0-9]+)", options: .regularExpression) {
            return Int(substring(with: range).components(separatedBy: "=")[1])
        }
        return nil
    }
}

public struct MastodonCollection<Item: Decodable> {
    public let items: [Item]
    public let previous: Pagination?
    public let next: Pagination?

    public init(items: [Item], previous: Pagination? = nil, next: Pagination? = nil) {
        self.items = items
        self.previous = previous
        self.next = next
    }

    static func paginationFromLinkHeader(_ header: String) -> (next: Pagination?, previous: Pagination?) {
        var previous: Pagination? = nil
        var next: Pagination? = nil
        header
            .components(separatedBy: ",")
            .forEach({ (values) in
                var sinceId: Int? = nil
                var maxId: Int? = nil
                let components = values.components(separatedBy: ";")
                    .map({
                        $0
                            .trimmingCharacters(in: CharacterSet.whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                    })
                let urlString = components[0]
                switch components[1] {
                case "rel=\"prev\"":
                    sinceId = urlString.fetchParameter("since_id")
                    maxId = urlString.fetchParameter("max_id")
                    previous = (sinceId: sinceId, maxId: maxId)
                case "rel=\"next\"":
                    sinceId = urlString.fetchParameter("since_id")
                    maxId = urlString.fetchParameter("max_id")
                    next = (sinceId: sinceId, maxId: maxId)
                default:
                    break;
                }
            })
        return (next: next, previous: previous)
    }

}

public extension Response {
    public func mapCollection<T: Decodable>(_ item: T.Type) throws -> MastodonCollection<T> {
        var previous: Pagination? = nil
        var next: Pagination? = nil

        if let httpResponse = response as? HTTPURLResponse {
            let headers = httpResponse.allHeaderFields
            if let linkHeader = headers["Link"] as? String {
                let result = MastodonCollection<T>.paginationFromLinkHeader(linkHeader)
                previous = result.previous
                next = result.next
            }
        }

        guard
            let json = try mapJSON() as? [Gloss.JSON]
            else {
                throw MoyaError.jsonMapping(self)
        }

        if let models = [T].from(jsonArray: json) {
            return MastodonCollection(items: models, previous: previous, next: next)
        } else {
            throw MoyaError.jsonMapping(self)
        }
    }
}

public extension ObservableType where E == Response {
    public func mapCollection<T: Decodable>(_ item: T.Type) -> Observable<MastodonCollection<T>> {
        return flatMap { (response) -> Observable<MastodonCollection<T>> in
            return Observable.just(try response.mapCollection(T.self))
        }
    }
}
