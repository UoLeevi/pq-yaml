// Use this file to write queries to test your data connector
let
    TestCases = {
        {"""double quoted string""", each _ = "double quoted string"},

        {"'single quoted string'", each _ = "single quoted string"},

        {"unquoted string", each _ = "unquoted string"},

        {"- one list item", each List.Single(_) = "one list item"},

        {"prop: value 1", each [prop] = "value 1"},

        {"
- item 1
- item 2
- item 3a: value 1
  item 3b: value 2
- item 4
", each List.Count(_) = 4}

    },

    Result = List.AllTrue(List.Transform(TestCases, each _{1}(Yaml.Parse(_{0}))))
in
    Result
