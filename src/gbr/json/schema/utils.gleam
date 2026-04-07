////
//// Utilities functions
////

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}

// Alias
//

type AnySchema =
  Dict(String, Any)

type AnySchemas =
  List(AnySchema)

/// The spec and decoder of an tool.
///
/// Tools are defined with only a decoder because
/// implementations of a tool can be sync or async.
///
/// See `Effect` for implementing tool handling.
///
pub type Tool(t, in, out) {
  Tool(spec: Spec(in, out), decoder: decode.Decoder(t))
}

/// Effect to call one generic tool
///
pub type Effect(return, tool, prompt) {
  // Need more information
  GetPrompt(prompt: prompt, resume: fn(AnySchemas) -> return)
  // call generic tool
  CallTool(tool: tool, resume: fn(Result(AnySchemas, String)) -> return)
  // done call generic tool
  Done(message: return)
}

/// The specification for a generic tool.
///
/// - name: Tool name (unique).
/// - title: Tool title.
/// - description: Tool description.
/// - input: Input request data tool.
/// - output: Output response data tool.
///
/// Generic types:
///
/// - in: Inbound data generic type
/// - out: Outbound data generic type
///
pub type Spec(in, out) {
  Spec(name: String, title: String, description: String, input: in, output: out)
}

/// Uses in definitions
///
pub type Never {
  Never(Never)
}

/// Generic any wrapper to native type
///
pub type Any {
  Object(Fields)
  Array(List(Any))
  Boolean(Bool)
  Integer(Int)
  Number(Float)
  String(String)
  BitArray(BitArray)
  Null
}

/// Any error generic type
///
/// - code: Indentification int.
/// - message: Message error.
/// - data: Any data error.
///
pub type AnyError {
  AnyError(code: Int, message: String, data: Any)
}

/// Represent fields of any types
///
pub type Fields =
  Dict(String, Any)

/// Decoder any value
///
pub fn any_decoder() {
  use <- decode.recursive
  decode.one_of(decode.map(fields_decoder(), Object), [
    decode.list(any_decoder()) |> decode.map(Array),
    decode.bool |> decode.map(Boolean),
    decode.int |> decode.map(Integer),
    decode.float |> decode.map(Number),
    decode.map(decode.optional(decode.string), fn(decoded) {
      case decoded {
        Some(str) -> String(str)
        None -> Null
      }
    }),
  ])
}

/// Any value to json
///
/// - any: Any type value
///
pub fn any_to_json(any) {
  case any {
    Object(fields) -> fields_to_json(fields)
    Array(list) -> json.array(list, any_to_json)
    Boolean(bool) -> json.bool(bool)
    Integer(int) -> json.int(int)
    Number(float) -> json.float(float)
    String(string) -> json.string(string)
    BitArray(bitarray) ->
      bitarray
      |> bit_array.base16_encode()
      |> json.string()
    Null -> json.null()
  }
}

/// Any value to dynamic
///
/// - any: Any type value
///
pub fn any_to_dynamic(any: Any) -> dynamic.Dynamic {
  case any {
    Object(fields) -> fields_to_dynamic(fields)
    Array(items) -> dynamic.list(list.map(items, any_to_dynamic))
    Boolean(bool) -> dynamic.bool(bool)
    Integer(int) -> dynamic.int(int)
    Number(float) -> dynamic.float(float)
    String(string) -> dynamic.string(string)
    BitArray(bitarray) -> dynamic.bit_array(bitarray)
    Null -> dynamic.nil()
  }
}

/// Convert list of tuple key and value json to object of any.
///
/// - entries: list of tuple #(String, json.Json)
///
pub fn object(entries: List(#(String, json.Json))) {
  list.filter(entries, fn(entry) {
    let #(_, v) = entry
    v != json.null()
  })
  |> json.object
}

/// Json dictionary
///
/// - dict: Dict type
/// - values: Function convert key to value json
///
pub fn dict(dict, values) {
  json.dict(dict, fn(x) { x }, values)
}

/// Decoder fields of any values
///
pub fn fields_decoder() {
  decode.dict(decode.string, any_decoder())
}

/// Json to array bits
///
/// - json: String json representation
///
pub fn json_to_bits(json) {
  json
  |> json.to_string
  |> bit_array.from_string
}

/// Fields of any values to json
///
/// - fields: Fields of any type values
///
pub fn fields_to_json(fields) {
  json.dict(fields, fn(x) { x }, any_to_json)
}

/// Fields of any type values to dynamic
///
/// - fields: Fields of any type values
///
pub fn fields_to_dynamic(fields) {
  dynamic.properties(
    fields
    |> dict.to_list
    |> list.map(fn(entry) {
      let #(key, value) = entry
      #(dynamic.string(key), any_to_dynamic(value))
    }),
  )
}

/// Default field to optional decode field
///
pub fn default_field(key, decoder, default, k) {
  decode.optional_field(
    key,
    default,
    decode.optional(decoder) |> decode.map(option.unwrap(_, or: default)),
    k,
  )
}

/// Helper to decode optional field
///
pub fn optional_field(key, decoder, k) {
  decode.optional_field(key, None, decode.optional(decoder), k)
}

/// Decode field discriminate another inner fields
///
pub fn discriminate(
  field: name,
  decoder: decode.Decoder(d),
  default: t,
  choose: fn(d) -> Result(decode.Decoder(t), String),
) -> decode.Decoder(t) {
  use on <- decode.optional_field(
    field,
    decode.failure(default, "Discriminator"),
    decode.map(decoder, fn(on) {
      case choose(on) {
        Ok(decoder) -> decoder
        Error(message) -> decode.failure(default, message)
      }
    }),
  )
  on
}

/// Decode to primitive decoder "any" OK
///
pub fn any() {
  decode.new_primitive_decoder("any", Ok)
}

// Experimental
//
// - [ ] How send and catch event via effect pattern
// - [ ] How decode additional with except

/// Decoder additional field
///
pub fn decode_additional(_except, _decoder, next) {
  // use r <- decode.then(decode.dict(decode.string, decoder))
  // let additional = dict.drop(r, except)
  // TODO
  use additional <- decode.then(decode.success(dict.new()))
  next(additional)
}

/// Set gleam-br header content to generated resource contents
///
/// - now: String format iso date time ref. now
/// - contents: Resource contents generated by gleam-br.
///
pub fn header_code_generated(now, contents) {
  "// Licensed under the Lucid License (Individual Sovereignty & Non-Aggression)
// See LICENSE file in the root of the repository.
//......................=#%%*:...............................
//....................:#@%##@@+..............................
//....................=@%****%@#.............................
//...................:@@#+=+**#@@=...........................
//...................*@#*===+***@@#..........................
//..................-@@*=====+***%@%-........................
//..................@@*=---==++***#@@*:......................
//.................*@#=-::--==+++***#@@@@@@@@@@@@@@@%+:......
//................+@@-:.:::--=++++************######%@%:.....
//.............+#@@%-:...:::--=++++++************###%@@-.....
//........:*%@@@%+-:......::--==+++++++++++++++*###%@@*......
//....-#@@@@%*+=:.........:::--=+++++++++++++======@@*.......
//..+@@@#*++=::::::......::::::.:::::::::::::-===+@@+........
//.:@@#**+=====--::::..........:::::-++=-:::-===+@@=.........
//.:%@%%##**+++=-:...........::::::*%*+#%=:-===*@@-..........
//..:*@@@%##*+-:::::-#%%#=::::::::=%+:::++-===*@%-...........
//.....+@@@#==--:::-@*::+@=::-::++::::::::-===@%-............
//.......-%@@*====--%-:::-::=#++#%:::::::-===+@#:............
//.........:#@@#==-::::::::::-**=-=+++++++####@@=............
//............#@@*=-:::::::::-=+++++++++++*###%@#:...........
//.............-@%+=-::::::-+++++++++++++++*##%@@-...........
//.............:%@+=-::::-++++++++++++++++++###%@#...........
//.............:#@+=-::-=++++**########***++*##%@@=..........
//..............#@*==:-+++*#####################%@@..........
//..............*@*==-++*#####%%@@@@@@%%#########@@=.........
//..............+@*==+######%@@@#-:-*%@@@@@@%%##%@@-.........
//..............=@#=+#####%@@%=..........:=#@@@@@@-..........
//..............=@#=*##%@@@#:................................
//..............:%@*%%@@%=...................................
//...............:*%%%*:.....................................
//
//
//###########################################################
//# Code auto generate with love by Gleam BR in:
//# " <> now <> "
//###########################################################
//
" <> contents
}
