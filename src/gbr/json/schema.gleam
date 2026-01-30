////
//// 🧙 Magic convert json schema to gleam code
////
//// Provides a JSON-based format to annotate, validate, and structure JSON documents.
//// It defines keywords to constrain data types (e.g., type, properties, items),
//// ensuring data consistency and interoperability across systems.
////
//// The specification is maintained by the [JSON Schema Organization](https://json-schema.org/).
////
//// > Thanks to crowdhailer :heart:
////

import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/time/duration
import gleam/time/timestamp

import glance
import glance_printer
import justin
import non_empty_list.{NonEmptyList}

import gbr/shared/error as e
import gbr/shared/lookup as l
import gbr/shared/utils as u

import gbr/json/schema/ast
import gbr/json/schema/lift
import gbr/json/schema/types

import gbr/json/schema/domain.{
  type Ref, type Schema, AllOf, AlwaysFails, AlwaysPasses, AnyOf, Array, Boolean,
  Enum, Inline, Integer, Null, Number, Object, OneOf, Ref, String,
}

/// Alias ref. json schema
///
pub type JsonSchema =
  dict.Dict(String, domain.Schema)

/// Alias ref. object schema
///
pub type ObjectSchema =
  List(#(String, Ref(Schema), Bool))

/// Load json schema from raw content.
///
/// - json: Raw json schema content.
/// - location: Selector location element to filter.
///
pub fn load(json: String, location: String) -> Result(String, String) {
  let decode =
    location
    |> json_schema_decoder()

  // MCP JSON-RPC definitions
  use definitions <- result.try(
    json.parse(json, decode)
    |> result.map_error(e.json_to_string),
  )

  // Json schema definitions to code
  definitions
  |> generate(location)
}

/// Generate gleam code from json schema by selector location.
///
/// - schema: Dict key: string and value: json schema
/// - location: Selector location element to filter.
///
pub fn generate(schema: JsonSchema, location: String) -> Result(String, String) {
  let now =
    timestamp.system_time()
    |> timestamp.to_rfc3339(duration.minutes(0))
  let set_header = u.header_code_generated(now, _)
  let location = "#/" <> location <> "/"

  schema
  |> map()
  |> code()
  |> run(location)
  |> result.map(set_header)
}

/// Json schema from field name
///
/// - field: Field name from json to decode
///
pub fn json_schema_decoder(field: String) -> decode.Decoder(JsonSchema) {
  decode.field(field, decode.dict(decode.string, decoder()), decode.success)
}

/// Parse json schema into glance ast tuple:
///
/// - #(CustomTypes, TypeAlias, Functions)
///
pub fn parse(schemas) {
  let #(internal, named) =
    list.map_fold(schemas |> dict.to_list, [], fn(acc, entry) {
      let #(name, schema) = entry
      let #(top, _nullable, acc) = lift.do_lift(Inline(schema), acc)
      #(acc, #(name, top))
    })
  let named =
    list.append(
      named,
      internal
        |> list.unique
        |> list.reverse
        |> list.map(fn(entry) {
          let #(hash, fields) = entry
          #(lift.content_id_to_fn_prefix(hash), lift.Compound(fields))
        }),
    )

  l.fold(named, #([], [], []), fn(acc, entry) {
    let #(name, top) = entry
    let #(custom_types, type_aliases, fns) = acc
    use enc_fn <- l.then(types.to_encode_fn(#(name, top)))
    use dec_fn <- l.then(types.to_decode_fn(#(name, top)))
    let fns = list.append(fns, [enc_fn, dec_fn])
    let name = ast.name_for_gleam_type(name)
    use #(custom_types, type_aliases) <- l.then(case top {
      lift.Named(name) -> {
        use type_ <- l.then(types.to_type(lift.Named(name)))
        l.Done(#(custom_types, [types.alias(name, type_), ..type_aliases]))
      }
      lift.Primitive(primitive) -> {
        use type_ <- l.then(types.to_type(lift.Primitive(primitive)))
        l.Done(#(custom_types, [types.alias(name, type_), ..type_aliases]))
      }
      lift.Array(items) -> {
        use type_ <- l.then(types.to_type(lift.Array(items)))
        l.Done(#(custom_types, [types.alias(name, type_), ..type_aliases]))
      }
      lift.Tuple(items) -> {
        use type_ <- l.then(types.to_type(lift.Tuple(items)))
        l.Done(#(custom_types, [types.alias(name, type_), ..type_aliases]))
      }
      lift.Compound(lift.Fields(properties, additional, required)) -> {
        use type_ <- l.then(types.custom_type(
          name,
          properties,
          additional,
          required,
        ))
        l.Done(#([type_, ..custom_types], type_aliases))
      }
      lift.Dictionary(values) -> {
        use type_ <- l.then(types.to_type(lift.Dictionary(values)))
        l.Done(#(custom_types, [types.alias(name, type_), ..type_aliases]))
      }
      lift.Unsupported -> {
        use type_ <- l.then(types.to_type(lift.Unsupported))
        l.Done(#(custom_types, [types.alias(name, type_), ..type_aliases]))
      }
    })
    l.Done(#(custom_types, type_aliases, fns))
  })
}

/// Decoder for the JSON Schema type
///
/// Use with `json.parse`
///
pub fn decoder() -> decode.Decoder(domain.Schema) {
  use <- decode.recursive()
  decode.one_of(
    {
      use #(type_, nullable_decoder) <- u.discriminate(
        "type",
        type_decoder(),
        Null(None, None, False),
      )
      case type_ {
        "boolean" ->
          {
            use nullable <- decode.then(nullable_decoder)
            use title <- decode.then(title_decoder())
            use description <- decode.then(description_decoder())
            use deprecated <- decode.then(deprecated_decoder())
            decode.success(Boolean(nullable, title, description, deprecated))
          }
          |> Ok
        "integer" ->
          {
            use multiple_of <- u.optional_field("multipleOf", decode.int)
            use maximum <- u.optional_field("maximum", decode.int)
            use exclusive_maximum <- u.optional_field(
              "exclusiveMaximum",
              decode.int,
            )
            use minimum <- u.optional_field("minimum", decode.int)
            use exclusive_minimum <- u.optional_field(
              "exclusiveMinimum",
              decode.int,
            )
            use nullable <- decode.then(nullable_decoder)
            use title <- decode.then(title_decoder())
            use description <- decode.then(description_decoder())
            use deprecated <- decode.then(deprecated_decoder())
            decode.success(Integer(
              multiple_of,
              maximum,
              exclusive_maximum,
              minimum,
              exclusive_minimum,
              nullable,
              title,
              description,
              deprecated,
            ))
          }
          |> Ok
        "number" ->
          {
            use multiple_of <- u.optional_field("multipleOf", decode.int)
            use maximum <- u.optional_field("maximum", decode.int)
            use exclusive_maximum <- u.optional_field(
              "exclusiveMaximum",
              decode.int,
            )
            use minimum <- u.optional_field("minimum", decode.int)
            use exclusive_minimum <- u.optional_field(
              "exclusiveMinimum",
              decode.int,
            )
            use nullable <- decode.then(nullable_decoder)
            use title <- decode.then(title_decoder())
            use description <- decode.then(description_decoder())
            use deprecated <- decode.then(deprecated_decoder())
            decode.success(Number(
              multiple_of,
              maximum,
              exclusive_maximum,
              minimum,
              exclusive_minimum,
              nullable,
              title,
              description,
              deprecated,
            ))
          }
          |> Ok

        "string" ->
          {
            use max_length <- u.optional_field("maxLength", decode.int)
            use min_length <- u.optional_field("minLength", decode.int)
            use pattern <- u.optional_field("pattern", decode.string)
            use format <- u.optional_field("format", decode.string)
            use nullable <- decode.then(nullable_decoder)
            use title <- decode.then(title_decoder())
            use description <- decode.then(description_decoder())
            use deprecated <- decode.then(deprecated_decoder())
            decode.success(String(
              max_length,
              min_length,
              pattern,
              format,
              nullable,
              title,
              description,
              deprecated,
            ))
          }
          |> Ok

        "null" ->
          {
            use title <- decode.then(title_decoder())
            use description <- decode.then(description_decoder())
            use deprecated <- decode.then(deprecated_decoder())
            decode.success(Null(title, description, deprecated))
          }
          |> Ok
        "array" ->
          {
            {
              use max_items <- u.optional_field("maxItems", decode.int)
              use min_items <- u.optional_field("minItems", decode.int)
              use unique_items <- u.default_field(
                "uniqueItems",
                decode.bool,
                False,
              )
              use items <- decode.field("items", ref_decoder(decoder()))
              use nullable <- decode.then(nullable_decoder)
              use title <- decode.then(title_decoder())
              use description <- decode.then(description_decoder())
              use deprecated <- decode.then(deprecated_decoder())
              decode.success(Array(
                max_items,
                min_items,
                unique_items,
                items,
                nullable,
                title,
                description,
                deprecated,
              ))
            }
          }
          |> Ok
        "object" ->
          {
            use properties <- decode.then(properties_decoder())
            use required <- decode.then(required_decoder())
            use additional_properties <- u.optional_field(
              "additionalProperties",
              ref_decoder(decoder()),
            )
            use max_properties <- u.optional_field("maxProperties", decode.int)
            // "Omitting this keyword has the same behavior as a value of 0"
            use min_properties <- u.default_field(
              "minProperties",
              decode.int,
              0,
            )
            use nullable <- decode.then(nullable_decoder)
            use title <- decode.then(title_decoder())
            use description <- decode.then(description_decoder())
            use deprecated <- decode.then(deprecated_decoder())
            decode.success(Object(
              properties,
              required,
              additional_properties,
              max_properties,
              min_properties,
              nullable,
              title,
              description,
              deprecated,
            ))
          }
          |> Ok
        type_ -> Error("valid schema type got: " <> type_)
      }
    },
    [
      decode.field(
        "allOf",
        non_empty_list_of_schema_decoder() |> decode.map(AllOf),
        decode.success,
      ),
      decode.field(
        "anyOf",
        non_empty_list_of_schema_decoder() |> decode.map(AnyOf),
        decode.success,
      ),
      decode.field(
        "oneOf",
        non_empty_list_of_schema_decoder() |> decode.map(OneOf),
        decode.success,
      ),
      decode.field(
        "enum",
        non_empty_list_of_any_decoder() |> decode.map(Enum),
        decode.success,
      ),
      decode.field(
        "const",
        u.any_decoder()
          |> decode.map(fn(value) { Enum(non_empty_list.single(value)) }),
        decode.success,
      ),
      decode.bool
        |> decode.map(fn(b) {
          case b {
            True -> AlwaysPasses
            False -> AlwaysFails
          }
        }),
      decode.dict(decode.string, decode.string)
        |> decode.map(fn(d) {
          case d == dict.new() {
            True -> AlwaysPasses
            False -> AlwaysFails
          }
        }),
    ],
  )
}

/// Convert a Schema to a gleam_json type.
///
/// encode this to a string using `json.to_string`
pub fn encode(schema) {
  case schema {
    Boolean(nullable:, title:, description:, deprecated:) ->
      json_object([
        #("type", Some(json.string("boolean"))),
        #("nullable", Some(json.bool(nullable))),
        #("title", option.map(title, json.string)),
        #("description", option.map(description, json.string)),
        #("deprecated", Some(json.bool(deprecated))),
      ])
    Integer(..) as int -> {
      json_object([
        #("type", Some(json.string("integer"))),
        #("multipleOf", option.map(int.multiple_of, json.int)),
        #("maximum", option.map(int.maximum, json.int)),
        #("exclusiveMaximum", option.map(int.exclusive_maximum, json.int)),
        #("minimum", option.map(int.minimum, json.int)),
        #("exclusiveMinimum", option.map(int.exclusive_minimum, json.int)),
        #("nullable", Some(json.bool(int.nullable))),
        #("title", option.map(int.title, json.string)),
        #("description", option.map(int.description, json.string)),
        #("deprecated", Some(json.bool(int.deprecated))),
      ])
    }
    Number(..) as number -> {
      json_object([
        #("type", Some(json.string("number"))),
        #("multipleOf", option.map(number.multiple_of, json.int)),
        #("maximum", option.map(number.maximum, json.int)),
        #("exclusiveMaximum", option.map(number.exclusive_maximum, json.int)),
        #("minimum", option.map(number.minimum, json.int)),
        #("exclusiveMinimum", option.map(number.exclusive_minimum, json.int)),
        #("nullable", Some(json.bool(number.nullable))),
        #("title", option.map(number.title, json.string)),
        #("description", option.map(number.description, json.string)),
        #("deprecated", Some(json.bool(number.deprecated))),
      ])
    }
    String(..) as string -> {
      json_object([
        #("type", Some(json.string("string"))),
        #("MaxLength", option.map(string.max_length, json.int)),
        #("MinLength", option.map(string.min_length, json.int)),
        #("Pattern", option.map(string.pattern, json.string)),
        #("Format", option.map(string.format, json.string)),
        #("nullable", Some(json.bool(string.nullable))),
        #("title", option.map(string.title, json.string)),
        #("description", option.map(string.description, json.string)),
        #("deprecated", Some(json.bool(string.deprecated))),
      ])
    }
    Null(..) as null -> {
      json_object([
        #("type", Some(json.string("null"))),
        #("title", option.map(null.title, json.string)),
        #("description", option.map(null.description, json.string)),
        #("deprecated", Some(json.bool(null.deprecated))),
      ])
    }
    Array(..) as array -> {
      json_object([
        #("type", Some(json.string("array"))),
        #("maxItems", option.map(array.max_items, json.int)),
        #("minItems", option.map(array.min_items, json.int)),
        #("uniqueItems", Some(json.bool(array.unique_items))),
        #("items", Some(ref_encode(array.items))),
        #("nullable", Some(json.bool(array.nullable))),
        #("title", option.map(array.title, json.string)),
        #("description", option.map(array.description, json.string)),
        #("deprecated", Some(json.bool(array.deprecated))),
      ])
    }
    Object(..) as object -> {
      json_object([
        #("type", Some(json.string("object"))),
        #(
          "properties",
          Some(json.dict(object.properties, fn(x) { x }, ref_encode)),
        ),
        #(
          "additionalProperties",
          option.map(object.additional_properties, ref_encode),
        ),
        #("maxProperties", option.map(object.max_properties, json.int)),
        #("minProperties", Some(json.int(object.min_properties))),
        #("required", Some(json.array(object.required, json.string))),
        #("nullable", Some(json.bool(object.nullable))),
        #("title", option.map(object.title, json.string)),
        #("description", option.map(object.description, json.string)),
        #("deprecated", Some(json.bool(object.deprecated))),
      ])
    }
    AllOf(varients) -> {
      json_object([
        #(
          "allOf",
          Some(json.array(non_empty_list.to_list(varients), ref_encode)),
        ),
      ])
    }
    AnyOf(varients) -> {
      json_object([
        #(
          "anyOf",
          Some(json.array(non_empty_list.to_list(varients), ref_encode)),
        ),
      ])
    }
    OneOf(varients) -> {
      json_object([
        #(
          "oneOf",
          Some(json.array(non_empty_list.to_list(varients), ref_encode)),
        ),
      ])
    }
    Enum(non_empty_list.NonEmptyList(value, [])) ->
      json_object([#("const", Some(u.any_to_json(value)))])
    Enum(values) -> {
      let values = non_empty_list.to_list(values)
      json_object([#("enum", Some(json.array(values, u.any_to_json)))])
    }
    AlwaysPasses -> json.bool(True)
    AlwaysFails -> json.bool(False)
  }
}

// PRIVATE
//

/// Generate json schema to gleam code content
///
fn code(schemas) -> l.Lookup(String) {
  use #(custom_types, type_aliases, functions) <- l.then(parse(schemas))

  glance.Module(
    imports(),
    defs(custom_types),
    defs(type_aliases),
    [],
    defs(functions),
  )
  |> glance_printer.print()
  |> l.Done
}

/// JSON-RPC definitions map with lift values.
///
/// > Throw panic if not is definition JSON-RPC.
///
fn map(defs) {
  defs
  |> dict.map_values(fn(key, value) { values_lift(key, value) })
}

/// Lift key/value values from JSON-RPC definition.
///
fn values_lift(key, value) {
  case is_request(key) || is_notification(key) {
    True -> lift_params(value)
    False -> value
  }
}

fn is_request(key) {
  case string.ends_with(key, "Request"), key {
    _, "ClientRequest" | _, "ServerRequest" | _, "JSONRPCRequest" -> False
    True, _ -> True
    False, _ -> False
  }
}

fn is_notification(key) {
  case string.ends_with(key, "Notification"), key {
    _, "ClientNotification" | _, "ServerNotification" | _, "JSONRPCNotification"
    -> False
    True, _ -> True
    False, _ -> False
  }
}

fn lift_params(value) {
  case value {
    domain.Object(properties: p, ..) ->
      case dict.size(p), dict.get(p, "method"), dict.get(p, "params") {
        2, Ok(domain.Inline(domain.String(..))), Ok(domain.Inline(params)) ->
          params
        _, _, _ ->
          panic as "[ERR] Def. should be method: string and params: object"
      }
    _ -> panic as "[ERR] Def. should be request: object"
  }
}

fn run(lookup, prefix) {
  case lookup {
    l.Lookup(ref, resume) ->
      case string.split_once(ref, prefix) {
        Ok(#("", inner)) ->
          resume(None, inner)
          |> run(prefix)
        _ -> Error("Unknown ref: " <> ref)
      }

    l.Done(value) -> Ok(value)
  }
}

fn imports() {
  [
    glance.Definition([], glance.Import("gbr/shared/utils", None, [], [])),
    glance.Definition([], glance.Import("gleam/dict", None, [], [])),
    glance.Definition([], glance.Import("gleam/dynamic/decode", None, [], [])),
    glance.Definition([], glance.Import("gleam/json", None, [], [])),
    glance.Definition(
      [],
      glance.Import(
        "gleam/option",
        None,
        [glance.UnqualifiedImport("Option", None)],
        [glance.UnqualifiedImport("None", None)],
      ),
    ),
  ]
}

fn defs(xs) {
  list.map(xs, glance.Definition([], _))
}

// PRIVATE
//

fn ref_decoder(of: decode.Decoder(t)) -> decode.Decoder(Ref(t)) {
  decode.one_of(
    {
      use ref <- decode.field("$ref", decode.string)
      use summary <- u.optional_field("summary", decode.string)
      use description <- u.optional_field("description", decode.string)
      decode.success(Ref(ref, summary, description))
    },
    [decode.map(of, Inline)],
  )
}

fn properties_decoder() {
  u.default_field(
    "properties",
    decode.dict(decode.string, ref_decoder(decoder())),
    dict.new(),
    decode.success,
  )
}

fn type_decoder() {
  decode.one_of(
    decode.string
      |> decode.map(fn(type_) { #(type_, nullable_decoder()) }),
    [
      decode.list(decode.string)
      |> decode.then(fn(types) {
        case types {
          [type_] -> decode.success(#(type_, nullable_decoder()))
          ["null", type_] | [type_, "null"] ->
            decode.success(#(type_, decode.success(True)))
          _ -> decode.failure(#("", nullable_decoder()), "Type")
        }
      }),
    ],
  )
}

fn non_empty_list_of_schema_decoder() {
  use list <- decode.then(decode.list(ref_decoder(decoder())))
  case list {
    [] -> decode.failure(NonEmptyList(Inline(AlwaysFails), []), "")
    [a, ..rest] -> decode.success(NonEmptyList(a, rest))
  }
}

fn non_empty_list_of_any_decoder() {
  use list <- decode.then(decode.list(u.any_decoder()))
  case list {
    [] -> decode.failure(NonEmptyList(u.Null, []), "")
    [a, ..rest] -> decode.success(NonEmptyList(a, rest))
  }
}

fn required_decoder() {
  u.default_field("required", decode.list(decode.string), [], decode.success)
}

fn nullable_decoder() {
  u.default_field("nullable", decode.bool, False, decode.success)
}

fn title_decoder() {
  u.optional_field("title", decode.string, decode.success)
}

fn description_decoder() {
  u.optional_field("description", decode.string, decode.success)
}

fn deprecated_decoder() {
  u.default_field("deprecated", decode.bool, False, decode.success)
}

fn ref_encode(ref) {
  case ref {
    Inline(schema) -> encode(schema)
    Ref(reference, ..) -> json.object([#("$ref", json.string(reference))])
  }
}

fn json_object(properties) {
  list.filter_map(properties, fn(property) {
    let #(key, value) = property
    case value {
      Some(value) -> Ok(#(key, value))
      None -> Error(Nil)
    }
  })
  |> json.object
}

pub fn name_for_gleam_type(in) {
  in
  |> prefix_signs
  |> replace_disallowed_charachters
  |> justin.pascal_case()
  |> prefix_numbers
}

fn prefix_signs(in) {
  let in = case string.starts_with(in, "-") {
    True -> "negative" <> in
    False -> in
  }
  case string.starts_with(in, "+") {
    True -> "positive" <> in
    False -> in
  }
}

fn replace_disallowed_charachters(in) {
  in
  |> string.replace("/", "_")
  |> string.replace("+", "_")
  // this is part of kebab casing
  // |> string.replace("-", "Minus")
  |> string.replace("^", "")
  |> string.replace("$", "")
}

fn prefix_numbers(in) {
  let needs_prefix =
    list.any(
      ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
      string.starts_with(in, _),
    )
  case needs_prefix {
    True -> "n" <> in
    False -> in
  }
}
