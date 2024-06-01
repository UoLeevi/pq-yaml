// This file contains your Data Connector logic
[Version = "1.0.0"]
section Yaml;

[DataSource.Kind="Yaml", Publish="Yaml.Publish"]
shared Yaml.Parse = let
    // see: https://yaml.org/spec/1.2.2

    Helper_ReadLine = (input as text) as record =>
        let
            // Extract text until end of line
            PositionOf_CrLf = Text.PositionOf(input, "#(cr)#(lf)"),
            PositionOf_Lf = Text.PositionOf(input, "#(lf)"),
            LineInfo = 
                if PositionOf_CrLf = -1 and PositionOf_Lf = -1 then [Line = input, End = Text.Length(input)]
                else if PositionOf_CrLf = -1 then [Line = Text.Start(input, PositionOf_Lf), End = PositionOf_Lf + 1]
                else if PositionOf_Lf = -1 then [Line = Text.Start(input, PositionOf_CrLf), End = PositionOf_CrLf + 2]
                else if PositionOf_CrLf < PositionOf_Lf then [Line = Text.Start(input, PositionOf_CrLf), End = PositionOf_CrLf + 2]
                else [Line = Text.Start(input, PositionOf_Lf), End = PositionOf_Lf + 1]
        in
            LineInfo,


    Helper_ReadIndentedLines = (input as text, minimumIndentation as number) as list =>
        List.Generate(
            () => [
                LineIndex = 0,
                RemainingText = input,
                LineIndentationPrefix = Text.Repeat(" ", minimumIndentation),
                NextLineInfo = Helper_ReadLine(input)
            ],
            each Text.StartsWith([NextLineInfo][Line], [LineIndentationPrefix]),
            each
                let
                    RemainingText = Text.Middle([RemainingText], [NextLineInfo][End]),
                    LineIndentationPrefix = if [LineIndex] <> 0
                        then [LineIndentationPrefix]
                        else Text.Repeat(" ", Text.Length([NextLineInfo][Line]) - Text.Length(Text.TrimStart([NextLineInfo][Line], " ")))
                in
                    [
                        LineIndex = [LineIndex] + 1,
                        RemainingText = RemainingText,
                        LineIndentationPrefix = LineIndentationPrefix,
                        NextLineInfo = Helper_ReadLine(RemainingText)
                    ],
            each [
                Line = if [LineIndex] = 0
                    then Text.TrimStart([NextLineInfo][Line], " ")
                    else Text.Middle([NextLineInfo][Line], Text.Length([LineIndentationPrefix])),
                End = [NextLineInfo][End]
            ]
        ),


    // https://yaml.org/spec/1.2.2/#rule-c-indicator
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

    // https://yaml.org/spec/1.2.2/#rule-c-flow-indicator
    FlowIndicators = {
        ",", // c-collect-entry
        "[", // c-sequence-start
        "]", // c-sequence-end
        "{", // c-mapping-start
        "}"  // c-mapping-end
    },

    Spec = {
        // Empty line
        {each Text.TrimStart([Line], " ") = "", each [
            Type = null,
            End = [Cursor_NextLine]
        ]},

        // Comment
        // https://yaml.org/spec/1.2.2/#rule-c-comment
        {each Text.StartsWith([Line], "#"), each [
            Type = null, // c-comment
            End = [Cursor_NextLine]
        ]},

        // Directives end marker
        // https://yaml.org/spec/1.2.2/#rule-c-directives-end
        {each Text.StartsWith([Line], "---"), each [
            Type = "c-directives-end",
            End = [Cursor] + 3
        ]},

        // Document end marker
        // https://yaml.org/spec/1.2.2/#rule-c-document-end
        {each Text.StartsWith([Line], "..."), each [
            Type = "c-document-end",
            End = [Cursor] + 3
        ]},

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

        // Single-quoted flow scalar indicator
        // https://yaml.org/spec/1.2.2/#rule-c-single-quote
        {each Text.StartsWith([Line], "'"), each
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

                TextAfterInitialSingleQuote = Text.Middle([String], [Cursor] + 1),
                Length = PositionOfEndOfString(TextAfterInitialSingleQuote) + 1,
                Text = Text.Replace(Text.Start(TextAfterInitialSingleQuote, Length - 2), "''", "'")
            in 
                [
                    Type = "string", // c-single-quote
                    Value = Text,
                    End = [Cursor] + Length
                ]
        },

        // Double-quoted flow scalar indicator
        // https://yaml.org/spec/1.2.2/#rule-c-double-quote
        {each Text.StartsWith([Line], """"), each
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

                RemainingText = Text.Middle([String], [Cursor]),
                Length = PositionOfEndOfString(RemainingText),
                Text = Text.Replace(Text.Replace(Text.Middle(RemainingText, 1, Length - 2), "\\", "\"), "\""", """")
            in 
                [
                    Type = "string", // c-double-quote
                    Value = Text,
                    End = [Cursor] + Length
                ]
        },

        // Mapping value indicator
        // https://yaml.org/spec/1.2.2/#rule-c-mapping-key
        {each Text.StartsWith([Line], ":"), each [
            Type = "c-mapping-value",
            End = [Cursor] + 1
        ]},

        // Literal block scalar indicator
        // https://yaml.org/spec/1.2.2/#rule-c-literal
        {each Text.StartsWith([Line], "|"), each
            let
                TextAfterIndicator = Text.Middle([String], [Cursor] + 1),
                HeaderLineInfo = Helper_ReadLine(TextAfterIndicator),
                TextAfterHeader = Text.Middle([String], [Cursor] + 1 + HeaderLineInfo[End]),
                BodyLineInfos = Helper_ReadIndentedLines(TextAfterHeader, [Indentation] + 1),

                FinalLineSuffix =
                    if HeaderLineInfo[Line] = "" then "#(lf)"
                    else if HeaderLineInfo[Line] = "+" then "#(lf)"
                    else if HeaderLineInfo[Line] = "-" then ""
                    else error "Syntax error: Invalid block scalar header",

                Text = Text.Combine(List.Transform(BodyLineInfos, each [Line]), "#(lf)") & FinalLineSuffix
            in
                [
                    Type = "string", // c-literal,
                    Value = Text,
                    End = [Cursor] + 1 + HeaderLineInfo[End] + List.Sum(List.Transform(BodyLineInfos, each [End]))
                ]
        },

        // Folded block scalar indicator
        // https://yaml.org/spec/1.2.2/#rule-c-folded
        {each Text.StartsWith([Line], ">"), each
            let
                TextAfterIndicator = Text.Middle([String], [Cursor] + 1),
                HeaderLineInfo = Helper_ReadLine(TextAfterIndicator),
                TextAfterHeader = Text.Middle([String], [Cursor] + 1 + HeaderLineInfo[End]),
                BodyLineInfos = Helper_ReadIndentedLines(TextAfterHeader, [Indentation] + 1),

                FinalLineSuffix =
                    if HeaderLineInfo[Line] = "" then "#(lf)"
                    else if HeaderLineInfo[Line] = "+" then "#(lf)"
                    else if HeaderLineInfo[Line] = "-" then ""
                    else error "Syntax error: Invalid block scalar header",

                Text = Text.Combine(List.Transform(BodyLineInfos, each [Line]), " ") & FinalLineSuffix
            in
                [
                    Type = "string", // c-folded,
                    Value = Text,
                    End = [Cursor] + 1 + HeaderLineInfo[End] + List.Sum(List.Transform(BodyLineInfos, each [End]))
                ]
        },

        // Directive indicator
        // https://yaml.org/spec/1.2.2/#rule-c-directive
        {each Text.StartsWith([Line], "%"), each [
            Type = "c-directive",
            End = [Cursor] + 1
        ]},

        // Alias node
        // https://yaml.org/spec/1.2.2/#rule-c-ns-alias-node
        {each Text.StartsWith([Line], "*"), each
            let
                LineAfterIndicator = Text.Middle([Line], 1),
                Delimiters = FlowIndicators & {" ", "#(tab)"},
                DelimiterPositions = {Text.Length(LineAfterIndicator)} & List.Select(
                    List.Transform(
                        Delimiters,
                        each Text.PositionOf(LineAfterIndicator, _)
                    ),
                    each _ > -1
                ),
                Text = Text.TrimEnd(Text.Start(LineAfterIndicator, List.Min(DelimiterPositions)))
            in 
                [
                    Type = "c-ns-alias-node",
                    Value = Text,
                    End = [Cursor] + Text.Length(Text) + 1
                ]
        },

        // Anchor property
        // https://yaml.org/spec/1.2.2/#rule-c-ns-anchor-property
        {each Text.StartsWith([Line], "&"), each
            let
                LineAfterIndicator = Text.Middle([Line], 1),
                Delimiters = FlowIndicators & {" ", "#(tab)"},
                DelimiterPositions = {Text.Length(LineAfterIndicator)} & List.Select(
                    List.Transform(
                        Delimiters,
                        each Text.PositionOf(LineAfterIndicator, _)
                    ),
                    each _ > -1
                ),
                Text = Text.TrimEnd(Text.Start(LineAfterIndicator, List.Min(DelimiterPositions)))
            in 
                [
                    Type = "c-ns-anchor-property",
                    Value = Text,
                    End = [Cursor] + Text.Length(Text) + 1
                ]
        },

        // Tag
        // https://yaml.org/spec/1.2.2/#rule-c-tag
        {each Text.StartsWith([Line], "!"), each
            let
                // TODO: Implement more strict parsing
                Line = [Line],
                Delimiters = {" ", "#(tab)"},
                DelimiterPositions = {Text.Length(Line)} & List.Select(
                    List.Transform(
                        Delimiters,
                        each Text.PositionOf(Line, _)
                    ),
                    each _ > -1
                ),
                Text = Text.TrimEnd(Text.Start(Line, List.Min(DelimiterPositions)))
            in 
                [
                    Type = "c-tag",
                    Value = Text,
                    End = [Cursor] + Text.Length(Text)
                ]
        },

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

        // Plain (unquoted) scalar
        // https://yaml.org/spec/1.2.2/#rule-ns-plain-first
        {each true, each
            let
                Line = [Line],
                DelimiterPositions = {Text.Length(Line)} & List.Select(
                    List.Transform(
                        Indicators,
                        each Text.PositionOf(Line, _)
                    ),
                    each _ > -1
                ),
                Text = Text.TrimEnd(Text.Start(Line, List.Min(DelimiterPositions)))
            in 
                [
                    Type = "string", // ns-plain-first
                    Value = Text,
                    End = [Cursor] + Text.Length(Text)
                ]
        }
    },

    Parser_AssertAndThenGetNextToken = (state as record, tokenType as text) as record =>
        Parser_GetNextToken(
            Parser_AssertTokenType(state, tokenType)
        ),

    Parser_AssertTokenType = (state as record, tokenType as text) as record =>
        if state[Token][Type] = tokenType then state
        else error Text.Format("Syntax error: Expected token type '#[Expected]' instead got '#[Actual]'", [
            Expected = tokenType,
            Actual = state[Token][Type]
        ]),
    
    Parser_GetNextToken = (state as record) as record =>
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
                    LineInfo = Helper_ReadLine(String),

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


    // Node parsing functions
    // - All node parsing funtions have following signature:
    //   (state as ParserState) as [State as ParserState, Node as Node]


    // https://yaml.org/spec/1.2.2/#block-sequences
    Parse_BlockSequence = (state as record) as record =>
        let
            // Save indentation level to determine scope
            Indentation = state[Indentation],

            // Move cursor to next token after list item indicator
            State_1 = Parser_GetNextToken(state),

            // Parse list item node
            R_1 = Parse_Node(State_1),
            Item = R_1[Node],
            State_2 = R_1[State]
        in
            // If end of list is reached, return the item in a list
            if   State_2[Token] = null 
              or State_2[Token][Type] <> "c-sequence-entry"
              or State_2[Indentation] < Indentation 
                then [State = State_2, Node = {Item}]
            
            // If the next token is a list item at the same indentation level, parse rest of the items and combine them into a list
            else 
                let
                    R_2 = @Parse_BlockSequence(State_2),
                    Rest = R_2[Node],
                    State_3 = R_2[State]
                in
                    [State = State_3, Node = {Item} & Rest],


    // https://yaml.org/spec/1.2.2/#flow-sequences
    Parse_FlowSequence = (state as record) as record =>
        // If next token is sequence end indicator, return empty list
        if state[Token][Type] = "c-sequence-end"
            then [State = Parser_GetNextToken(state), Node = {}]

        else
            let
                // Parse sequence entry
                R_1 = Parse_Node(state),
                Item = R_1[Node],
                State_1 = R_1[State]
            in
                // If next token is sequence end indicator, return list with one item
                if State_1[Token][Type] = "c-sequence-end"
                    then [State = Parser_GetNextToken(State_1), Node = {Item}]
                
                // Otherwise parse rest of the items and combine them into a list
                else 
                    let
                        State_2 = Parser_AssertAndThenGetNextToken(State_1, "c-collect-entry"),
                        R_2 = @Parse_FlowSequence(State_2),
                        Rest = R_2[Node],
                        State_3 = R_2[State]
                    in
                        [State = State_3, Node = {Item} & Rest],


    Parse_MappingKey = (state as record) as record =>
        let
            State_1 = Parser_GetNextToken(state),
            State_2 = Parser_GetNextToken(State_1)
        in
            if state[Token][Type] = "string"
                then [
                    State = Parser_AssertAndThenGetNextToken(State_1, "c-mapping-value"),
                    Node = state[Token][Value]
                ] 

            else if state[Token][Type] <> "c-mapping-key" then error "Syntax error"

            else if State_1[Token][Type] = "string"
                then [
                    State = Parser_AssertAndThenGetNextToken(State_2, "c-mapping-value"),
                    Node = State_1[Token][Value]
                ]
            
            else error "Non-string mapping keys are not implemented",


    // https://yaml.org/spec/1.2.2/#block-mappings
    Parse_BlockMapping = (state as record) as record =>
        let
            // Save indentation level to determine scope
            Indentation = state[Indentation],

            // Parse mapping key
            R_1 = Parse_MappingKey(state),
            MappingKey = R_1[Node],
            State_1 = R_1[State],

            // Parse mapping value node
            R_2 = Parse_Node(State_1),
            MappingValue = R_2[Node],
            State_2 = R_2[State],

            // Mapping as record
            Mapping = Record.FromList({MappingValue}, {MappingKey})
        in
            // If end of record is reached, return the key and value as record
            if   State_2[Token] = null
              or State_2[Token][Type] <> "string"
              or State_2[Indentation] < Indentation
                then [State = State_2, Node = Mapping]
            
            // If the next token is a string at the same indentation level and following token is mapping value indicator, parse rest of the propeties and combine them into a record
            else 
                let
                    State_3 = Parser_GetNextToken(State_2)
                in
                    if State_3[Token][Type] <> "c-mapping-value" then [State = State_2, Node = Mapping]
                    else
                        let
                            R_3 = @Parse_BlockMapping(State_2),
                            Rest = R_3[Node],
                            State_4 = R_3[State]
                        in
                            [State = State_4, Node = Record.Combine({Mapping} & {Rest})],


    // https://yaml.org/spec/1.2.2/#flow-mappings
    Parse_FlowMapping = (state as record) as record =>
        // If next token is mapping end indicator, return empty record
        if state[Token][Type] = "c-mapping-end"
            then [
                State = Parser_GetNextToken(state),
                Node = []
            ]

        else
            let
                // Parse mapping key
                R_1 = Parse_MappingKey(state),
                MappingKey = R_1[Node],
                State_1 = R_1[State],

                // Parse mapping value node
                R_2 = Parse_Node(State_1),
                MappingValue = R_2[Node],
                State_2 = R_2[State],

                // Mapping as record
                Mapping = Record.FromList({MappingValue}, {MappingKey})
            in
                // If next token is mapping end indicator, return record
                if State_2[Token][Type] = "c-mapping-end" then [State = Parser_GetNextToken(State_2), Node = Mapping]
                
                // Otherwise parse rest of the propeties and combine them into a record
                else 
                    let
                        State_3 = Parser_AssertAndThenGetNextToken(State_2, "c-collect-entry"),
                        R_3 = @Parse_FlowMapping(State_3),
                        Rest = R_3[Node],
                        State_4 = R_3[State]
                    in
                        [State = State_4, Node = Record.Combine({Mapping} & {Rest})],

    Parse_NodeAlias = (state as record) as record =>
        let
            Alias = state[Token][Value],
            Node = Record.Field(state[Aliases], Alias),
            Metadata = Record.AddField(Value.Metadata(Node), "Alias", Alias)
        in
            [
                State = Parser_GetNextToken(state),
                Node = Node meta Metadata
            ],

    Parse_NodeTag = (state as record) as record =>
        let
            Tag = state[Token][Value],
            State_1 = Parser_GetNextToken(state),
            
            R_1 = Parse_Node(State_1),
            Node = R_1[Node],
            State_2 = R_1[State],
            
            Metadata = Record.AddField(Value.Metadata(Node), "Tag", Tag)
        in
            if Record.HasFields(Value.Metadata(Node), "Tag")
                then error "Syntax error: node can have only a single tag"
                else [
                    State = State_2,
                    Node = Node meta Metadata
                ],

    Parse_NodeAnchor = (state as record) as record =>
        let
            Anchor = state[Token][Value],
            State_1 = Parser_GetNextToken(state),

            R_1 = Parse_Node(State_1),
            Node = R_1[Node],
            State_2 = R_1[State],
            
            State_3 = Record.TransformFields(State_2, {
                {"Aliases", each Record.AddField(_, Anchor, Node)}
            }),

            Metadata = Record.AddField(Value.Metadata(Node), "Anchor", Anchor)
        in
            if Record.HasFields(Value.Metadata(Node), "Anchor")
                then error "Syntax error: node can have only a single anchor"
                else [
                    State = State_3,
                    Node = Node meta Metadata
                ],

    Parse_Node = (state as record) as record => 
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

            else if TokenType = "c-ns-alias-node" then Parse_NodeAlias(state)

            else if TokenType = "c-tag" then Parse_NodeTag(state)

            else if TokenType = "c-ns-anchor-property" then Parse_NodeAnchor(state)

            else if TokenType = "c-sequence-start" then Parse_FlowSequence(NextState)

            else if TokenType = "c-sequence-entry" then Parse_BlockSequence(state)
            
            else if TokenType = "c-mapping-start" then Parse_FlowMapping(NextState)
            
            else if TokenType = "c-mapping-key" then Parse_BlockMapping(state)

            else if TokenType = "string" and NextTokenType = "c-mapping-value" then Parse_BlockMapping(state)
            
            else if TokenType = "string" then [State = NextState, Node = state[Token][Value]]
            
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
        ],
        Aliases = []
    ]),

    Parse = (optional yaml as text) =>
        let
            State_Initial = Parser_Initialize(yaml)
        in
            if State_Initial[Cursor] = State_Initial[End] 
                then null meta [Message = "Empty YAML document"]
                else Parse_Node(State_Initial)[Node]
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
