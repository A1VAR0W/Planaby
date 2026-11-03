import AppIntents

struct FocusMethodEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Método de concentración"
    static let defaultQuery = FocusMethodQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(_ method: FocusMethod) {
        id = method.id
        name = method.name
    }
}

struct FocusMethodQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [FocusMethodEntity] {
        MethodLibrary.shared.all.filter { identifiers.contains($0.id) }.map(FocusMethodEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [FocusMethodEntity] {
        MethodLibrary.shared.all.map(FocusMethodEntity.init)
    }
}
