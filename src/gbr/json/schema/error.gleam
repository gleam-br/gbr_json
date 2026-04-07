////
//// 🚨 Error generic type translate to string
////

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string

import gbr/json/schema/utils as u

/// Any error to json.
///
/// - err: Any generic error.
///
pub fn to_json(err: u.AnyError) -> json.Json {
  let u.AnyError(code:, message:, data:) = err

  json.object([
    #("code", json.int(code)),
    #("message", json.string(message)),
    #("data", u.any_to_json(data)),
  ])
}

/// Any error decoder.
///
pub fn decoder() -> decode.Decoder(u.AnyError) {
  use code <- decode.field("code", decode.int)
  use message <- decode.field("message", decode.string)
  use data <- decode.optional_field("data", u.Null, u.any_decoder())

  u.AnyError(code:, message:, data:)
  |> decode.success()
}

/// Any error to string.
///
/// - err: Any generic error.
///
pub fn to_string(err: u.AnyError) {
  to_json(err)
  |> json.to_string()
}

/// decode.DecodeError type to string
///
pub fn decode_to_string(err: decode.DecodeError) -> String {
  let decode.DecodeError(expected:, found:, path:) = err

  "Error decode expected: "
  <> expected
  <> "; found="
  <> found
  <> "; path="
  <> string.join(path, ".")
}

/// json.DecodeError type to string
///
pub fn json_to_string(err: json.DecodeError) -> String {
  case err {
    json.UnexpectedEndOfInput -> "Json unexpected end of input"
    json.UnexpectedByte(byte) -> "Json unexpected byte " <> byte
    json.UnexpectedSequence(seq) -> "Json unexpected sequence " <> seq
    json.UnableToDecode(dec_errors) ->
      "Json error unable to decode:\n"
      <> {
        use er <- list.map(dec_errors)
        "Expected: "
        <> er.expected
        <> " Found: "
        <> er.found
        <> ": "
        <> string.join(er.path, ",")
      }
      |> string.join("\n")
  }
}
