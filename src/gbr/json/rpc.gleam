////
//// JSON-RPC
////

import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

import gbr/shared/error as e
import gbr/shared/utils as u

/// JSON-RPC spec version
///
const jsonrpc: String = "2.0"

/// Identification generic type
///
/// Could be a string id or number id.
///
pub type Id {
  StringId(String)
  NumberId(Int)
}

/// Request/Notification types.
///
/// - r: Request generic type.
/// - n: Response generic type.
///
pub type Request(r, n) {
  Request(version: String, id: Id, value: r)
  Notification(version: String, value: n)
}

/// Response type.
///
/// - t: Response generic type.
///
pub type Response(t) {
  Response(version: String, id: Id, return: Result(t, u.AnyError))
}

/// Identification generic type decoder.
///
pub fn id_decoder() -> decode.Decoder(Id) {
  let id_string =
    decode.string
    |> decode.map(StringId)
  let id_number =
    decode.int
    |> decode.map(NumberId)

  decode.one_of(id_string, [id_number])
}

/// Identification generic type encode.
///
/// - id: Id type instance.
///
pub fn id_encode(id: Id) -> json.Json {
  case id {
    StringId(string) -> json.string(string)
    NumberId(number) -> json.int(number)
  }
}

/// Identification to string.
///
/// - id: Id type instance.
///
pub fn id_to_string(id: Id) -> String {
  case id {
    NumberId(id) -> int.to_string(id)
    StringId(id) -> id
  }
}

/// New JSON-RPC request
///
/// - id: Identification type request.
/// - value: Value from request.
///
pub fn request(id: Id, value: a) -> Request(a, b) {
  Request(version: jsonrpc, id:, value:)
}

/// New JSON-RPC notification.
///
/// - value: Value from request
///
pub fn notification(value: a) -> Request(b, a) {
  Notification(version: jsonrpc, value:)
}

/// New JSON-RPC response.
///
/// - id: Identification type of response.
/// - result: Result instance or any error.
///
pub fn response(id: Id, result: Result(b, u.AnyError)) -> Response(b) {
  Response(jsonrpc, id, result)
}

/// New JSON-RPC result.
///
/// - id: Identificarion type of response.
/// - result: Instance result of Ok response .
///
pub fn result(id: Id, result: a) -> Response(a) {
  Response(jsonrpc, id, Ok(result))
}

/// Get JSON-RPC request decoder.
///
/// - request_decoders: List of any req decoders.
/// - notification_decoders: List of any notify decoders.
/// - zero: Initial notifiication instance.
///
pub fn request_decoder(
  request_decoders: List(#(String, decode.Decoder(r))),
  notification_decoders: List(#(String, decode.Decoder(n))),
  zero: n,
) -> decode.Decoder(Request(r, n)) {
  use version <- decode.field("jsonrpc", decode.string)
  use id <- u.optional_field("id", id_decoder())
  use method <- decode.field("method", decode.string)

  case id {
    Some(id) ->
      case list.key_find(request_decoders, method) {
        Ok(decoder) -> {
          use maybe <- u.optional_field("params", u.any())
          // In mcp there are optional fields
          let params = option.unwrap(maybe, dynamic.properties([]))
          case decode.run(params, decoder) {
            Ok(value) -> decode.success(Request(version:, id:, value:))
            Error(_reason) ->
              decode.failure(Notification(version, zero), "params")
          }
        }
        Error(Nil) ->
          decode.failure(
            Notification(version, zero),
            "missing decoder " <> method,
          )
      }
    None ->
      case list.key_find(notification_decoders, method) {
        Ok(decoder) -> {
          use maybe <- u.optional_field("params", u.any())

          // In mcp there are optional fields
          let params = option.unwrap(maybe, dynamic.properties([]))
          case decode.run(params, decoder) {
            Ok(value) -> decode.success(Notification(version:, value:))
            Error(_reason) ->
              decode.failure(Notification(version, zero), "params")
          }
        }
        Error(Nil) ->
          decode.failure(
            Notification(version, zero),
            "missing decoder " <> method,
          )
      }
  }
}

/// Get JSON-RPC request encoder.
///
/// - request: Request generic type.
/// - request_enconde: Request type encode to json.
/// - notification_encoder: Notification type encode to json.
///
pub fn request_encode(
  request: Request(req, not),
  request_encode: fn(req) -> #(String, Option(json.Json)),
  notification_encode: fn(not) -> #(String, Option(json.Json)),
) -> json.Json {
  case request {
    Request(version:, id:, value:) -> {
      let #(method, params) = request_encode(value)
      json.object([
        #("jsonrpc", json.string(version)),
        #("id", id_encode(id)),
        #("method", json.string(method)),
        ..case params {
          None -> []
          Some(params) -> [
            #("params", params),
          ]
        }
      ])
    }
    Notification(version:, value:) -> {
      let #(method, params) = notification_encode(value)
      json.object([
        #("jsonrpc", json.string(version)),
        #("method", json.string(method)),
        ..case params {
          None -> []
          Some(params) -> [
            #("params", params),
          ]
        }
      ])
    }
  }
}

/// Get response decoder.
///
/// - return_decoder: Decoder to return value.
///
pub fn response_decoder(
  return_decoder: decode.Decoder(a),
) -> decode.Decoder(Response(a)) {
  use version <- decode.field("jsonrpc", decode.string)
  use id <- decode.field("id", id_decoder())
  use return <- decode.then(
    decode.one_of(
      {
        use value <- decode.field("result", return_decoder)
        decode.success(Ok(value))
      },
      [
        {
          use reason <- decode.field("error", e.decoder())
          decode.success(Error(reason))
        },
      ],
    ),
  )

  Response(version:, id:, return:)
  |> decode.success()
}

/// Get response encode.
///
/// - response: Response type of generic instance.
/// - return_encode: Function map to json generic instance.
///
pub fn response_encode(
  response: Response(a),
  return_encode: fn(a) -> json.Json,
) -> json.Json {
  let Response(version:, id:, return:) = response

  json.object([
    #("jsonrpc", json.string(version)),
    #("id", id_encode(id)),
    case return {
      Ok(value) -> #("result", return_encode(value))
      Error(obj) -> #("error", e.to_json(obj))
    },
  ])
}
