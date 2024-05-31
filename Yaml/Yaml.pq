// This file contains your Data Connector logic
[Version = "1.0.0"]
section Yaml;

[DataSource.Kind="Yaml", Publish="Yaml.Publish"]
shared Yaml.Parse = let
    // see: https://yaml.org/spec/1.2.2

    Indicators = {
        "-",  // c-sequence-entry
        "?",  // c-mapping-key
        ":",  // c-mapping-value
        ",",  // c-collect-entry
        "[",  // c-sequence-start
        "]",  // c-sequence-end
        "{",  // c-mapping-start
        "}",  // c-mapping-end
        "#",  // c-comment
        "&",  // c-anchor
        "*",  // c-alias
        "!",  // c-tag
        "|",  // c-literal
        ">",  // c-folded
        "'",  // c-single-quote
        """", // c-double-quote
        "%",  // c-directive
        "@",  // c-reserved
        "`"   // c-reserved
    },

    Spec = {
        // Empty line
        {each Text.TrimStart([Line], " ") = "", each [
            Type = null,
            End = [Cursor_NextLine]
        ]},

        // Comment
        {each Text.StartsWith([Line], "#"), each [
            Type = null,
            End = [Cursor_NextLine]
        ]},

        // Document start and end
        {each Text.StartsWith([Line], "---"), each error "Tokenizer not implemented: '---'"},
        {each Text.StartsWith([Line], "..."), each error "Tokenizer not implemented: '...'"},

        // Block sequence entry indicator
        // https://yaml.org/spec/1.2.2/#rule-c-sequence-entry
        {each Text.StartsWith([Line], "-"), each [
            Type = "c-sequence-entry",
            End = [Cursor] + 1
        ]},

        // Mapping key indicator
        // https://yaml.org/spec/1.2.2/#rule-c-mapping-key
        {each Text.StartsWith([Line], "?"), each [
            Type = "c-mapping-key",
            End = [Cursor] + 1
        ]},

        // Double quoted string
        {each Text.StartsWith([Line], """"), each
            let
                RemainingText = Text.Middle([String], [Cursor]),
                Value = Parse_DoubleQuotedString(RemainingText),
                End = [Cursor] + Value.Metadata(Value)[End]
            in 
                [
                    Type = "string",
                    Value = Value,
                    End = End
                ]
        },

        // Single quoted string
        {each Text.StartsWith([Line], "'"), each
            let
                RemainingText = Text.Middle([String], [Cursor]),
                Value = Parse_SingleQuotedString(RemainingText),
                End = [Cursor] + Value.Metadata(Value)[End]
            in 
                [
                    Type = "string",
                    Value = Value,
                    End = End
                ]
        },

        // Mapping value indicator
        // https://yaml.org/spec/1.2.2/#rule-c-mapping-key
        {each Text.StartsWith([Line], ":"), each [
            Type = "c-mapping-value",
            End = [Cursor] + 1
        ]},

        // Multiline literal
        {each Text.StartsWith([Line], "|"), each error "Tokenizer not implemented: '|'"},

        // Multiline folded
        {each Text.StartsWith([Line], ">"), each error "Tokenizer not implemented: '>'"},

        // Directive
        {each Text.StartsWith([Line], "%"), each error "Tokenizer not implemented: '%'"},

        // Alias node
        {each Text.StartsWith([Line], "*"), each error "Tokenizer not implemented: '*'"},

        // Anchor node
        {each Text.StartsWith([Line], "&"), each error "Tokenizer not implemented: '&'"},

        // Tag property
        {each Text.StartsWith([Line], "!"), each error "Tokenizer not implemented: '!'"},

        // Flow collection entry indicator
        // https://yaml.org/spec/1.2.2/#rule-c-collect-entry
        {each Text.StartsWith([Line], ","), each [
            Type = "c-collect-entry",
            End = [Cursor] + 1
        ]},

        // Flow sequence indicators
        // https://yaml.org/spec/1.2.2/#rule-c-sequence-start
        {each Text.StartsWith([Line], "["), each [
            Type = "c-sequence-start",
            End = [Cursor] + 1
        ]},
        // https://yaml.org/spec/1.2.2/#rule-c-sequence-end
        {each Text.StartsWith([Line], "]"), each [
            Type = "c-sequence-end",
            End = [Cursor] + 1
        ]},

        // Flow mapping indicators
        // https://yaml.org/spec/1.2.2/#rule-c-mapping-start
        {each Text.StartsWith([Line], "{"), each [
            Type = "c-mapping-start",
            End = [Cursor] + 1
        ]},
        // https://yaml.org/spec/1.2.2/#rule-c-mapping-end
        {each Text.StartsWith([Line], "}"), each [
            Type = "c-mapping-end",
            End = [Cursor] + 1
        ]},

        // Unquoted string
        {each true, each
            let
                Value = Parse_UnquotedString([Line], Indicators),
                End = [Cursor] + Value.Metadata(Value)[End]
            in 
                [
                    Type = "string",
                    Value = Value,
                    End = End
                ]
        }
    },

    Parser_AssertAndThenGetNextToken = (state, tokenType as text) =>
        Parser_GetNextToken(
            Parser_AssertTokenType(state, tokenType)
        ),

    Parser_AssertTokenType = (state, tokenType as text) =>
        if state[Token][Type] = tokenType then state
        else error Text.Format("Syntax error: Expected token type '#[Expected]' instead got '#[Actual]'", [
            Expected = tokenType,
            Actual = state[Token][Type]
        ]),
    
    Parser_GetNextToken = (state) =>
        let
            // Update cursor to point to the end of previous token
            State_0 = Record.TransformFields(state, {
                {"Cursor", each state[Token][End]}
            })
        in
            // If end is reached, return with token type null
            if State_0[Cursor] = State_0[End] then Record.TransformFields(State_0, {
                {"Token", each [
                    Type = null,
                    End = State_0[End]
                ]}
            })
            else
                let
                    // Remaining string to parse
                    String = Text.Middle(State_0[String], State_0[Cursor]),

                    // Extract text until end of line
                    PositionOf_CrLf = Text.PositionOf(String, "#(cr)#(lf)"),
                    PositionOf_Lf = Text.PositionOf(String, "#(lf)"),
                    LineInfo = 
                        if PositionOf_CrLf = -1 and PositionOf_Lf = -1 then [Line = String, End = Text.Length(String)]
                        else if PositionOf_CrLf = -1 then [Line = Text.Start(String, PositionOf_Lf), End = PositionOf_Lf + 1]
                        else if PositionOf_Lf = -1 then [Line = Text.Start(String, PositionOf_CrLf), End = PositionOf_CrLf + 2]
                        else if PositionOf_CrLf < PositionOf_Lf then [Line = Text.Start(String, PositionOf_CrLf), End = PositionOf_CrLf + 2]
                        else [Line = Text.Start(String, PositionOf_Lf), End = PositionOf_Lf + 1],

                    // Remove leading spaces
                    Line_IndentationRemoved = Text.TrimStart(LineInfo[Line], " "),
                    Indentation = Text.Length(LineInfo[Line]) - Text.Length(Line_IndentationRemoved),

                    // Update state
                    State_1 = Record.TransformFields(State_0, {
                        {"Cursor", each _ + Indentation},
                        {"Cursor_NextLine", each State_0[Cursor] + LineInfo[End]},
                        {"Line", each Line_IndentationRemoved},
                        {"Indentation", each Indentation}
                    }),

                    // Get next token
                    Token = List.Last(
                        List.Generate(
                            () => 0,
                            each not Spec{_}{0}(State_1),
                            each _ + 1,
                            each Spec{_ + 1}{1}
                        ),
                        List.First(Spec){1}
                    )(State_1),

                    // Update state
                    State_2 = Record.TransformFields(State_1, {
                        {"Token", each Token}
                    })
                in
                    if Token[Type] = null
                        then @Parser_GetNextToken(State_2)
                        else State_2,

    Parse_SingleQuotedString = (input as text) as text => 
        let
            PositionOfEndOfString = (input as text) as number =>
                let
                    PositionOf_SingleQuote = Text.PositionOf(input, "'"),
                    Length = Text.Length(input)
                in
                    if PositionOf_SingleQuote = Length - 1
                        then PositionOf_SingleQuote + 1
                        else
                            let
                                TextAfterSingleQuote = Text.Middle(input, PositionOf_SingleQuote + 1),
                                CountOfSingleQuotes = 1 + List.Count(List.Generate(
                                    () => 1,
                                    each Text.StartsWith(TextAfterSingleQuote, Text.Repeat("'", _)),
                                    each _ + 1
                                ))
                    in
                        if Number.IsOdd(CountOfSingleQuotes)
                            then PositionOf_SingleQuote + CountOfSingleQuotes
                            else PositionOf_SingleQuote + CountOfSingleQuotes + 1 + @PositionOfEndOfString(Text.Middle(TextAfterSingleQuote, CountOfSingleQuotes)),

            TextAfterInitialSingleQuote = Text.Middle(input, 1),
            End = PositionOfEndOfString(TextAfterInitialSingleQuote) + 1,
            Text = Text.Replace(Text.Start(TextAfterInitialSingleQuote, End - 2), "''", "'")
        in
            Text meta [End = End],


    Parse_DoubleQuotedString = (input as text) as text => 
        let
            PositionOfEndOfString = (input as text) as number =>
            let
                PositionOf_DoubleQuote = Text.PositionOf(Text.Middle(input, 1), """"),
                IsEscaped = Number.IsOdd(List.Count(List.Generate(
                    () => 0,
                    each _ < PositionOf_DoubleQuote and Text.At(input, PositionOf_DoubleQuote - _) = "\",
                    each _ + 1
                )))
            in
                if IsEscaped
                    then PositionOf_DoubleQuote + 2 + @PositionOfEndOfString(Text.Middle(input, PositionOf_DoubleQuote + 2))
                    else PositionOf_DoubleQuote + 2,

            End = PositionOfEndOfString(input),
            Text = Text.Replace(Text.Replace(Text.Middle(input, 1, End - 2), "\\", "\"), "\""", """")
        in
            Text meta [End = End],


    Parse_UnquotedString = (input as text, optional delimiters as list) as text =>
        let
            DelimiterPositions = {Text.Length(input)} & List.Select(
                List.Transform(
                    delimiters ?? {},
                    each Text.PositionOf(input, _)
                ),
                each _ > -1
            ),
            Text = Text.TrimEnd(Text.Start(input, List.Min(DelimiterPositions))),
            End = Text.Length(Text)
        in
            Text meta [End = End],

    Parse_BlockSequence = (state) as list =>
        let
            // Save indentation level to determine scope
            Indentation = state[Indentation],

            // Move cursor to next token after list item indicator
            State_1 = Parser_GetNextToken(state),

            // Parse list item node
            Item = Parse_Node(State_1),

            // State of the parser after item was parsed
            State_2 = Value.Metadata(Item)
        in
            // If end of list is reached, return the item in a list
            if State_2[Token] = null then {Item} meta State_2
            else if State_2[Token][Type] <> "c-sequence-entry" then {Item} meta State_2
            else if State_2[Indentation] < Indentation then {Item} meta State_2
            
            // If the next token is a list item at the same indentation level, parse rest of the items and combine them into a list
            else 
                let
                    Rest = @Parse_BlockSequence(State_2),
                    List = {Item} & Rest,
                    State_3 = Value.Metadata(Rest)
                in
                    List meta State_3,

    Parse_FlowSequence = (state) as list =>
        // If next token is sequence end indicator, return empty list
        if state[Token][Type] = "c-sequence-end"
            then {} meta Parser_GetNextToken(state)

        else
            let
                // Parse sequence entry
                Item = Parse_Node(state),

                // State of the parser after item was parsed
                State_1 = Value.Metadata(Item)
            in
                // If next token is sequence end indicator, return list with one item
                if State_1[Token][Type] = "c-sequence-end" then {Item} meta Parser_GetNextToken(State_1)
                
                // Otherwise parse rest of the items and combine them into a list
                else 
                    let
                        State_2 = Parser_AssertAndThenGetNextToken(State_1, "c-collect-entry"),
                        Rest = @Parse_FlowSequence(State_2),
                        List = {Item} & Rest,
                        State_3 = Value.Metadata(Rest)
                    in
                        List meta State_3,

    Parse_MappingKey = (state) as text =>
        let
            State_1 = Parser_GetNextToken(state),
            State_2 = Parser_GetNextToken(State_1)
        in
            if state[Token][Type] = "string"
                then state[Token][Value] 
                    meta Parser_AssertAndThenGetNextToken(State_1, "c-mapping-value")

            else if state[Token][Type] <> "c-mapping-key" then error "Syntax error"

            else if State_1[Token][Type] = "string"
                then State_1[Token][Value]
                    meta Parser_AssertAndThenGetNextToken(State_2, "c-mapping-value")
            
            else error "Non-string mapping keys are not implemented",

    Parse_BlockMapping = (state) as record =>
        let
            // Save indentation level to determine scope
            Indentation = state[Indentation],

            // Property key is the value of current string token
            PropertyKey = Parse_MappingKey(state),

            // State of the parser after mapping value indicator
            State_1 = Value.Metadata(PropertyKey),

            // Parse property value node
            PropertyValue = Parse_Node(State_1),

            // State of the parser after value was parsed
            State_2 = Value.Metadata(PropertyValue),

            // Property and value as record
            PropertyRecord = Record.FromList({PropertyValue}, {PropertyKey})
        in
            // If end of record is reached, return the property and value as record
            if State_2[Token] = null then PropertyRecord meta State_2
            else if State_2[Token][Type] <> "string" then PropertyRecord meta State_2
            else if State_2[Indentation] < Indentation then PropertyRecord meta State_2
            
            // If the next token is a string at the same indentation level and following token is property indicator, parse rest of the propeties and combine them into a record
            else 
                let
                    State_3 = Parser_GetNextToken(State_2)
                in
                    if State_3[Token][Type] <> "c-mapping-value" then PropertyRecord meta State_2
                    else
                        let
                            Rest = @Parse_BlockMapping(State_2),
                            Record = Record.Combine({PropertyRecord} & {Rest}),
                            State_4 = Value.Metadata(Rest)
                        in
                            Record meta State_4,

    Parse_FlowMapping = (state) as record =>
        // If next token is mapping end indicator, return empty record
        if state[Token][Type] = "c-mapping-end"
            then [] meta Parser_GetNextToken(state)

        else
            let
                // Property key is the value of current string token
                PropertyKey = Parse_MappingKey(state),

                // State of the parser after mapping value indicator
                State_1 = Value.Metadata(PropertyKey),

                // Parse property value node
                PropertyValue = Parse_Node(State_1),

                // State of the parser after value was parsed
                State_2 = Value.Metadata(PropertyValue),

                // Property and value as record
                PropertyRecord = Record.FromList({PropertyValue}, {PropertyKey})
            in
                // If next token is mapping end indicator, return record
                if State_2[Token][Type] = "c-mapping-end" then PropertyRecord meta Parser_GetNextToken(State_2)
                
                // Otherwise parse rest of the propeties and combine them into a record
                else 
                    let
                        State_3 = Parser_AssertAndThenGetNextToken(State_2, "c-collect-entry"),
                        Rest = @Parse_FlowMapping(State_3),
                        Record = Record.Combine({PropertyRecord} & {Rest}),
                        State_4 = Value.Metadata(Rest)
                    in
                        Record meta State_4,
    
    Parse_Scalar = (state) => error "Not implemented: Parse_Scalar",

    Parse_Node = (state) => 
        /*
          Node
          : Sequence
          : Mapping
          | Scalar
          ;
        */
        let
            TokenType = state[Token][Type],
            NextState = Parser_GetNextToken(state),
            NextTokenType = NextState[Token][Type]
        in
            if state[Cursor] = state[End] then error "Syntax error: empty node"

            else if TokenType = "c-sequence-start" then Parse_FlowSequence(NextState)

            else if TokenType = "c-sequence-entry" then Parse_BlockSequence(state)
            
            else if TokenType = "c-mapping-start" then Parse_FlowMapping(NextState)
            
            else if TokenType = "c-mapping-key" then Parse_BlockMapping(state)
            
            else if TokenType = "string" and NextTokenType = "c-mapping-value" then Parse_BlockMapping(state)
            
            else if TokenType = "string" then state[Token][Value] meta NextState
            
            else error Text.Format("Syntax error: unexpected token '#[TokenType]'", [TokenType = state[Token][Type]]),

    Parser_Initialize = (yaml as text) => Parser_GetNextToken([
        String = yaml,
        End = Text.Length(yaml),
        Cursor = 0,
        Cursor_LineStart = 0,
        Cursor_NextLine = 0,
        Line = "",
        Indentation = 0,
        Token = [
            Type = null,
            End = 0
        ]
    ]),

    Parse = (optional yaml as text) =>
        let
            State_Initial = Parser_Initialize(yaml)
        in
            Parse_Node(State_Initial)
in
    Parse meta [
        GetTokens = (yaml as text) => List.Generate(
            () => Parser_Initialize(yaml),
            each [Token][Type] <> null,
            each Parser_GetNextToken(_),
            each [Token]
        )
    ];


// Data Source Kind description
Yaml = [
    Authentication = [
        // Key = [],
        // UsernamePassword = [],
        // Windows = [],
        Anonymous = []
    ]
];

// Data Source UI publishing description
Yaml.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = Yaml.Icons,
    SourceTypeImage = Yaml.Icons
];

Yaml.Icons = [
    Icon16 = { Extension.Contents("Yaml16.png"), Extension.Contents("Yaml20.png"), Extension.Contents("Yaml24.png"), Extension.Contents("Yaml32.png") },
    Icon32 = { Extension.Contents("Yaml32.png"), Extension.Contents("Yaml40.png"), Extension.Contents("Yaml48.png"), Extension.Contents("Yaml64.png") }
];
