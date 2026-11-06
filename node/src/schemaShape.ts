/**
 * Which fields an audience's schema has, as far as the SDK's documents need to know. The API leaves a module's fields
 * out of an audience that hasn't installed it (Facebook Pages, Google Places, RSVP, Ticketing, Friends…), and asking
 * for one fails the whole operation with `undefinedField`; the SDK builds its documents from this.
 *
 * `fields` is each type's fields by type; null assumes every field is there (before the SDK has had to ask).
 */
export class SchemaShape {
  private readonly fields: ReadonlyMap<string, ReadonlySet<string>> | null;

  constructor(fields: Record<string, Iterable<string>> | ReadonlyMap<string, ReadonlySet<string>> | null) {
    if (fields === null) {
      this.fields = null;
    } else if (fields instanceof Map) {
      this.fields = fields;
    } else {
      this.fields = new Map(Object.entries(fields).map(([type, names]) => [type, new Set(names)]));
    }
  }

  /** Whether `type` has `field`; true for everything before the SDK has asked. */
  has(type: string, field: string): boolean {
    if (this.fields === null) return true;
    return this.fields.get(type)?.has(field) ?? false;
  }

  /** Assumes every field is there: each operation's first try, so an audience with every module needs one call. */
  static readonly EVERYTHING = new SchemaShape(null);
}
