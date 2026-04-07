////
//// JSON-RPC errors.
////
//// MCP prompt error
//// ?? TODO ??
////

import gleam/dict
import gleam/dynamic/decode
import gleam/list
import gleam/string

import gbr/json/schema/utils as u

/// Any error to method not avaiable.
///
/// - method: Method name.
///
pub fn method_not_available(method) {
  u.AnyError(
    code: -32_601,
    message: "Method unavailable: " <> method,
    data: u.Object(dict.from_list([#("method", u.String(method))])),
  )
}

/// Used for unknown and unavailable.
///
/// - tool: Unknown generic tool.
///
pub fn unknown_tool(tool) {
  u.AnyError(
    code: -32_602,
    message: "Unknown tool: " <> tool,
    data: u.Object(dict.from_list([#("tool", u.String(tool))])),
  )
}

pub fn unknown_prompt(prompt) {
  u.AnyError(
    code: -32_602,
    message: "Unknown prompt: " <> prompt,
    data: u.Object(dict.from_list([#("prompt", u.String(prompt))])),
  )
}

pub fn invalid_log_level(level) {
  u.AnyError(
    code: -32_602,
    message: "Invalid log level: " <> level,
    data: u.Object(dict.from_list([#("level", u.String(level))])),
  )
}

pub fn invalid_arguments(tool, decode) {
  let reason =
    list.map(decode, fn(error) {
      let decode.DecodeError(expected:, found:, path:) = error
      u.Object(
        dict.from_list([
          #("expected", u.String(expected)),
          #("found", u.String(found)),
          #("path", u.String(string.join(path, "."))),
        ]),
      )
    })
    |> u.Array
  u.AnyError(
    code: -32_602,
    message: "Invalid arguments for tool: " <> tool,
    data: u.Object(
      dict.from_list([#("tool", u.String(tool)), #("reason", reason)]),
    ),
  )
}

pub fn resource_not_found(uri) {
  u.AnyError(
    code: -32_002,
    message: "Resource not found",
    data: u.Object(dict.from_list([#("uri", u.String(uri))])),
  )
}
