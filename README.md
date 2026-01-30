[![Package Version](https://img.shields.io/hexpm/v/gbr_json)](https://hex.pm/packages/gbr_json)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gbr_json/)

# 📃 JSON & JSON Schema

JSON Schema library to load into AST and gen gleam code with definition types.

## Roadmap

- [ ] Update dep `glance` from 3.x to 6.x
  - [ ] Fix `glance_printer` to work with `6.x`
- [ ] Update json schema to https://json-schema.org/draft/2020-12/schema

## Running

```sh
gleam add gbr_json
```

```gleam
import simplifile

import gbr/json/schema

pub fn main() -> Nil {
  let path = "./priv/2025-06-18-schema.json"
  let field = "definitions"

  let content = path
  |> simplifile.read()
  |> result.map_error(fn(err) {
    "[ERR] Reading " <> path <> ": " <> string.inspect(err)
  })

  case schema.load(content, field) {
    Ok(output) -> io.println("> Definitions:\n" <> output)
    Error(err) -> io.println_error(err)
  }
}
```

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
