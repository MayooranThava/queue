import SwiftData

/// Version 1 is the schema already stored by TestFlight.
///
/// Those builds created `QueueLocalStore` from the top-level `@Model` types in
/// `TaskEntity.swift`, with no migration plan. V1 lists those same types. It does
/// not nest them, rename them, or change stored properties. Nesting would change
/// the Swift type (for example `TaskEntity` to `QueueSchemaV1.TaskEntity`) and
/// can change the entity name SwiftData writes into the store.
///
/// `Schema.Version(1, 0, 0)` is also the default version of an unversioned
/// `Schema([…])`, which is what shipping builds saved.
enum QueueSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskEntity.self,
            FocusSessionEntity.self,
            XPTransactionEntity.self,
            UserPreferencesEntity.self,
        ]
    }
}

/// Opens a V1 store as-is. Add a stage only when a later schema exists.
///
/// ## Adding V2
///
/// Do not edit stored properties on the V1 model classes. Those classes describe
/// the store already on device; changing them changes V1, and existing installs
/// will no longer match a schema in this plan.
///
/// 1. Add `enum QueueSchemaV2: VersionedSchema` with
///    `versionIdentifier = Schema.Version(2, 0, 0)`.
/// 2. For a model that does not change, keep referencing the V1 type
///    (`TaskEntity.self`, and so on). For a model that changes, declare a new
///    nested `@Model` inside `QueueSchemaV2` and point call sites at it (a
///    typealias is fine). On a renamed stored property, keep the old column:
///    `@Attribute(originalName: "oldName")`.
/// 3. Append `QueueSchemaV2.self` to `schemas` after V1. Never remove or reorder
///    a version that has shipped.
/// 4. Append one new stage. Do not rewrite a stage that has shipped.
///
/// Lightweight migration (new optional property, new model, or a rename that
/// sets `originalName`):
///
/// ```swift
/// static var stages: [MigrationStage] {
///     [
///         MigrationStage.lightweight(
///             fromVersion: QueueSchemaV1.self,
///             toVersion: QueueSchemaV2.self
///         )
///     ]
/// }
/// ```
///
/// Custom migration, when a lightweight stage cannot express the change
/// (a new type for an existing column, splitting or merging models, backfill).
/// `willMigrate` still sees V1. `didMigrate` sees V2. Throw to cancel. Do not
/// delete or replace the store file; a thrown migration leaves the previous
/// file in place.
///
/// ```swift
/// MigrationStage.custom(
///     fromVersion: QueueSchemaV1.self,
///     toVersion: QueueSchemaV2.self,
///     willMigrate: { context in
///         // Copy V1 values onto the fields V2 expects, then save `context`.
///     },
///     didMigrate: { context in
///         // Check invariants. Throw if the migrated rows are not safe to keep.
///     }
/// )
/// ```
enum QueueMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [QueueSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
