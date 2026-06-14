[Version = "1.0.9"]
section atlassianJiraConnector;

// Helper function to load .pqm files
Extension.LoadFunction = (fileName as text) =>
  let
      binary = Extension.Contents(fileName),
      asText = Text.FromBinary(binary)
  in
      try
        Expression.Evaluate(asText, #shared)
      catch (e) =>
        error [
            Reason = "Extension.LoadFunction Failure",
            Message.Format = "Loading '#{0}' failed - '#{1}': '#{2}'",
            Message.Parameters = {fileName, e[Reason], e[Message]},
            Detail = [File = fileName, Error = e]
        ];

//Load Module Groups
JiraAPI = Extension.LoadFunction("jiraAPI.pqm");
JiraInsights = Extension.LoadFunction("jiraInsights.pqm");
JiraSchema = Extension.LoadFunction("jiraSchema.pqm");
JiraTestSupport = Extension.LoadFunction("jiraTestSupport.pqm");
helperFunctions = Extension.LoadFunction("helperFunctions.pqm");
authHelper = Extension.LoadFunction("authHelper.pqm");

// Load individual API functions
buildJqlQuery = JiraAPI[buildJqlQuery];
DiscoverMaxResults = JiraAPI[DiscoverMaxResults];
jiraDataRetrievalSimple = JiraAPI[jiraDataRetrievalSimple];
jiraDataRetrievalPaginated = JiraAPI[jiraDataRetrievalPaginated];
getPolarisInsights = JiraInsights[SafeGetAllPolarisInsights];

// Load schema functions
issuesFieldsList = JiraSchema[issuesFieldsList];
JiraKnownFields = JiraSchema[JiraKnownFields];
InferJiraFieldType = JiraSchema[InferJiraFieldType];
ApplyJiraSchema = JiraSchema[ApplyJiraSchema];

// Load test support functions
ExtractTestIssuesData = JiraAPI[ExtractTestIssuesData];
CreateMockProjects = JiraTestSupport[CreateMockProjects];
Table.ToNavigationTable = helperFunctions[Table.ToNavigationTable];
ValidateUrlScheme = helperFunctions[ValidateUrlScheme];

//Load Auth Helper Functions
deBugCredentials = authHelper[debugCredentials];
GetOAuthConfig = authHelper[GetOAuthConfig];
startLogin = authHelper[startLogin];
finishLogin = authHelper[finishLogin]; 
refreshAccessToken = authHelper[refreshAccessToken];


// Implementation function (internal)
JiraImpl = (
    baseUrl as text,
    fieldList as nullable text,
    projectKeys as nullable text,
    jqlQuery as nullable text,
    jqlOrderBy as nullable text,
    testDataOverride as nullable record
) => jiraNavTbl(
    baseUrl,
    fieldList,
    projectKeys,
    jqlQuery,
    jqlOrderBy,
    testDataOverride
);

// Main entry point function
[DataSource.Kind="Atlassian_Jira_Connector.Kind", Publish="Atlassian_Jira_Connector.Publish"]
shared Jira = (
    #"Company Atlassian URL" as text,
    optional #"Field List (comma separated, e.g., summary,created)" as text,
    optional #"Project Keys (comma separated, e.g., PROJ1,PROJ2)" as text,
    optional #"JQL Filter (e.g., created>=-365d, status=""Open"") — default: created>=-365d" as text,
    optional #"JQL Order By (e.g., priority DESC, created DESC)" as text
) => jiraNavTbl(
    #"Company Atlassian URL",
    #"Field List (comma separated, e.g., summary,created)",
    #"Project Keys (comma separated, e.g., PROJ1,PROJ2)",
    #"JQL Filter (e.g., created>=-365d, status=""Open"") — default: created>=-365d",
    #"JQL Order By (e.g., priority DESC, created DESC)",
    null
);

// This function is for SDK testing only. It is not published.
shared JiraTest = (
    #"Company Atlassian URL" as text,
    optional fieldList as text,
    optional projectKeys as text,
    optional jqlQuery as text,
    optional jqlOrderBy as text,
    optional testDataOverride as record
) =>
    jiraNavTbl(#"Company Atlassian URL", fieldList, projectKeys, jqlQuery, jqlOrderBy, testDataOverride);



// OAuth Default Configuration works with Power BI Desktop and in theory Power BI Service
OAuthConfig = GetOAuthConfig();

// OAuth configuration for Power BI Desktop? In testing Desktop Accepts azure gateway (default value).
GatewayOAuthOverrides = 
    let
        override = [redirect_uri = "https://oauth.powerbi.com/views/oauthredirect.html"]
    in
        GetOAuthConfig(override);

// Data Source Kind description
Atlassian_Jira_Connector.Kind = [
    Properties = [
        SupportsEncryption = true,
        SupportsPerUserCredentials = true
    ],
    
    TestConnection = (dataSourcePath) =>
        let
            json = Json.Document(dataSourcePath),
            baseUrl = json[#"Company Atlassian URL"]
        in
            {"Jira", baseUrl},

    Authentication = [
        OAuth = [
            StartLogin = (resourceURL, state, display) => startLogin(resourceURL, state, display, OAuthConfig),
            FinishLogin = (context, callbackUri, state) => finishLogin(context, callbackUri, state, OAuthConfig),
            Refresh = (resourceURL, refresh_token) => refreshAccessToken(resourceURL, refresh_token, OAuthConfig),
            Label = "OAuth 2.0"
        ],
//comment out above and un-comment to build *.mez that uses PowerBI Oauth address
/*
        OAuth = [
            StartLogin = (resourceURL, state, display) => startLogin(resourceURL, state, display, GatewayOAuthOverrides),
            FinishLogin = (context, callbackUri, state) => finishLogin(context, callbackUri, state, GatewayOAuthOverrides),
            Refresh = (resourceURL, refresh_token) => refreshAccessToken(resourceURL, refresh_token, GatewayOAuthOverrides),
            Label = "OAuth 2.0 (On-Premise Gateway)"
        ],
*/
        Key = [
            KeyLabel = "API Token",
            Label = "API Token Authentication"
        ],
        UsernamePassword = [
            Username = "Email",
            PasswordLabel = "API Token",
            Label = "Basic Authentication"
        ]
    ],
    Label = "Atlassian Jira"
];


// Data Source UI publishing description
Atlassian_Jira_Connector.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://github.com/rpiboy-79/atlassianJiraConnector",
    SourceImage = atlassianJiraConnector.Icons,
    SourceTypeImage = atlassianJiraConnector.Icons
];

// icon resources
atlassianJiraConnector.Icons = [
    Icon16 = { Extension.Contents("atlassianJiraConnector16.png"), Extension.Contents("atlassianJiraConnector20.png"), Extension.Contents("atlassianJiraConnector24.png"), Extension.Contents("atlassianJiraConnector32.png") },
    Icon32 = { Extension.Contents("atlassianJiraConnector32.png"), Extension.Contents("atlassianJiraConnector40.png"), Extension.Contents("atlassianJiraConnector48.png"), Extension.Contents("atlassianJiraConnector64.png") }
];

//Universal Dynamic Jira Query Function
jiraQuery =
    (
        url as text, 
        queryPath as text, 
        optional jqlProjectKey as nullable text,
        optional fieldList as nullable list,
        optional jqlString as nullable text,
        optional jqlOrderByString as nullable text,
        optional discoverLimits as nullable logical,
        optional useSimpleRetrieval as nullable logical,
        optional testOverride as nullable record
    ) =>
        let
        // Handle optional parameters with defaults
            actualJqlProjectKey = if jqlProjectKey = null then null else jqlProjectKey,
            actualFieldsList = if fieldList = null then null else fieldList,
            actualJqlString = if jqlString = null then null else jqlString,
            actualJqlOrderBy = if jqlOrderByString = null then null else jqlOrderByString,
            shouldDiscoverLimits = if discoverLimits = null then false else discoverLimits,
            useSimple = if useSimpleRetrieval = null then true else useSimpleRetrieval,
            useTestData = if testOverride = null then null else testOverride,
            fieldsText = if actualFieldsList = null then null else Text.Combine(actualFieldsList, ","),

        //somewhere in here build full query
        jqlQuery = buildJqlQuery(actualJqlProjectKey, actualJqlString, actualJqlOrderBy),

        // DATA RETRIEVAL: Choose between simple or paginated
            CombinedData = if useSimple then
                jiraDataRetrievalSimple(
                    url,
                    queryPath,
                    jqlQuery,
                    fieldsText,
                    useTestData
                )
            else
                jiraDataRetrievalPaginated(
                    url,
                    queryPath,
                    jqlQuery,
                    fieldsText,
                    useTestData
                ),

        // TRANSFORMATION LOGIC:
            ConvertToTable = Table.FromList(CombinedData, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
            
            // Dynamic field expansion
            ExpandedTable =
                let
                // First expand the main issue fields (id, key, fields, etc.)
                // self and expand are Jira API internals — excluded unless explicitly requested.
                    firstRecord = if Table.RowCount(ConvertToTable) > 0 then ConvertToTable{0}[Column1] else null,
                    allTopLevelFields = if firstRecord <> null then Record.FieldNames(firstRecord) else {},
                    autoExclude = {"self", "expand", "id"},
                    topLevelFields = List.Select(allTopLevelFields, each
                        not List.Contains(autoExclude, _) or
                        (actualFieldsList <> null and List.Contains(actualFieldsList, _))
                    ),

                    expandedTop = if List.Count(topLevelFields) > 0 then
                        Table.ExpandRecordColumn(ConvertToTable, "Column1", topLevelFields, topLevelFields)
                    else
                        ConvertToTable,
                    
                // Check if we have a 'fields' column to expand (Jira issue data)
                    hasFieldsColumn = List.Contains(Table.ColumnNames(expandedTop), "fields"),
                    
                    expandedFields = if hasFieldsColumn and actualFieldsList <> null then
                    // Expand the nested 'fields' record with the requested field list
                        Table.ExpandRecordColumn(
                            expandedTop, 
                            "fields", 
                            List.RemoveItems(actualFieldsList, {"id", "key"}), // Remove id,key as they're already top-level
                            List.RemoveItems(actualFieldsList, {"id", "key"})
                        )
                    else if hasFieldsColumn then
                    // Dynamic expansion of fields if we don't have a specific field list
                        let
                            sampleFieldsRecord = if Table.RowCount(expandedTop) > 0 then 
                                expandedTop{0}[fields] else null,
                            fieldsToExpand = if sampleFieldsRecord <> null then 
                                Record.FieldNames(sampleFieldsRecord) else {}
                        in
                            if List.Count(fieldsToExpand) > 0 then
                                Table.ExpandRecordColumn(expandedTop, "fields", fieldsToExpand, fieldsToExpand)
                            else
                                expandedTop
                    else
                        expandedTop
                in
                    expandedFields,
            FinalTable = ApplyJiraSchema(ExpandedTable)
        in
            FinalTable;

// function to create the Issues sub-navigation table
createIssuesNavigationTable = 
    (projectTables as list) as table =>
        let
            source = Table.FromRows(
                projectTables,
                {"Name", "Data", "ItemKind", "ItemName", "IsLeaf"}
            ),
            navTable = Table.ToNavigationTable(
                source, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf"
            )
        in
            navTable;

// Navigation Table
jiraNavTbl =
    (
        companyURL as text,
        optional fields as text,
        optional projectKeys as text,
        optional jqlString as text,
        optional jqlOrderBy as text,
        optional testOverride as nullable record
    ) =>
        let
            credentials = try Extension.CurrentCredential() otherwise null,
        //temporay credentials debugging, return if needed to inspect credentials object
            deBugCredentials = deBugCredentials(credentials),

            AuthType =
                if credentials <> null
                then if credentials[AuthenticationKind] = "OAuth"
                    then "OAuth3LO"
                    else if credentials[AuthenticationKind] = "Key"
                        then "ApiToken"
                    else "BasicAuth"
                else "Legacy",

            baseURL =
                if AuthType = "OAuth3LO"
                then credentials[Properties][api_base_url]
                else companyURL,

            fieldsDynamic =
                if fields = null
                then issuesFieldsList
                else
                    List.Transform(
                        List.RemoveNulls(List.Transform(
                            Text.Split(fields, ","),
                            each if Text.Trim(_) = "" then null else Text.Trim(_)
                        )),
                        each _
                    ),

            // Default JQL filter when none is provided — prevents accidental full-table scans.
            effectiveJql = if jqlString = null or Text.Trim(jqlString) = "" then "created >= -365d" else jqlString,

            //if projectKeys = null, then check JQLstring for "project = " if project = is TRUE then get string after project = before AND/OR/(
            //how to extend for multiple project =, use list...
            //pass to project Validation so that we validate only the projects included in the JQLstring
            //allows a user to skip project keys and provide a fully qualified JQL string, but will prevent attempting to iterate over projects where the fully custom JQL string won't work
            //pass result to requested Projects either null or result of extraction from JQL query


            //is this called anywhere besides projectValidation?
            requestedProjects = 
                if projectKeys = null then 
                    {} 
                else 
                    List.Transform(
                        List.RemoveNulls(List.Transform(
                            Text.Split(projectKeys, ","), 
                            each if Text.Trim(_) = "" then null else Text.Trim(Text.Upper(_))
                        )),
                        each _
                    ),

            URL = ValidateUrlScheme(baseURL),

            allProjects =
                if testOverride <> null then
                    let
                        testIssues = ExtractTestIssuesData(testOverride)
                    in
                        CreateMockProjects(testIssues)
                else
                    jiraQuery(
                        URL, //url
                        "rest/api/3/project", //queryPath
                        null, //jqlProjectKey
                        null, //fieldList
                        null, //jqlString
                        null, //jqlOrderByString
                        null, //discoverLimits
                        false, //useSimpleRetrieval
                        null //testOverride
                    ),//uses advanced query since project retrieval is not paginated to begin with

            projectValidation = 
                let
                    validProjectKeys = Table.Column(allProjects, "key"),
                    
                    // Separate valid and invalid keys
                    validKeys = List.Select(requestedProjects, each List.Contains(validProjectKeys, _)),
                    invalidKeys = List.Select(requestedProjects, each not List.Contains(validProjectKeys, _)),
                    
                    // Use all projects if no filter specified, otherwise use validated subset
                    finalKeys =
                        if List.Count(requestedProjects) = 0
                        then validProjectKeys
                        else validKeys,
                    
                    filteredProjects = Table.SelectRows(allProjects, 
                        each List.Contains(finalKeys, [key])
                    ),
                    
                    // Create validation report
                    validationReport = #table(
                        {"Metric", "Value", "Details"},
                        {
                            {"Total Available Projects", Table.RowCount(allProjects), ""},
                            {"Requested Projects", List.Count(requestedProjects), Text.Combine(requestedProjects, ", ")},
                            {"Valid Requested", List.Count(validKeys), Text.Combine(validKeys, ", ")},
                            {"Invalid Requested", List.Count(invalidKeys), Text.Combine(invalidKeys, ", ")},
                            {"Final Project Count", Table.RowCount(filteredProjects), ""},
                            {"JQL Filter Applied", effectiveJql, if jqlString = null or Text.Trim(jqlString) = "" then "No filter supplied — defaulted to created >= -365d" else "User supplied"}
                        }
                    )
                in
                    [
                        Projects = filteredProjects,
                        ValidKeys = validKeys,
                        InvalidKeys = invalidKeys,
                        Report = validationReport,
                        HasInvalidKeys = List.Count(invalidKeys) > 0
                    ],
            
            getProjects = projectValidation[Projects],

            issues =
                let
                    getIssues = Table.AddColumn(getProjects, "Issues",
                        each jiraQuery(
                            URL,
                            "rest/api/3/search/jql",
                            "project=" & [key],
                            fieldsDynamic,
                            effectiveJql,
                            jqlOrderBy,
                            false,
                            false,
                            testOverride
                        )
                    ),
                    issuesWithErrorHandling = Table.TransformColumns(getIssues, {"Issues", each 
                        try _
                        catch (e) => 
                            #table(
                                {"Error Type", "Details"}, 
                                {
                                    {"Failed to retrieve issues", e[Reason]? },
                                    {"Error Message", e[Message]? },
                                    {"Check project permissions", "Verify project key and access rights"}
                                }
                            )
                    })
                in
                    issuesWithErrorHandling,

            //Get Jira Insights where applicable
            processInsights =
                let
                    hasJPD = List.Contains(getProjects[projectTypeKey], "product_discovery")
                in
                    AuthType = "OAuth3LO" and hasJPD,
            cloudId = credentials[Properties][cloud_id],
            accessToken = credentials[access_token],
            jpdProjects =
                if processInsights then
                    let
                        filterRows = Table.SelectRows(getProjects, each ([projectTypeKey] = "product_discovery")),
                        selectColumns = Table.SelectColumns(filterRows,{"id", "key", "projectTypeKey", "name"}),
                        mergeQueries = Table.NestedJoin(selectColumns, {"id"}, issues, {"id"}, "issueData", JoinKind.LeftOuter),
                        expandIssues = Table.ExpandTableColumn(mergeQueries, "issueData", {"Issues"}, {"Issues"}),
                        transformTable = Table.TransformColumns(expandIssues, { "Issues", each Table.SelectColumns(_, {"id", "key"})})
                    in
                        transformTable
                else
                    #table(
                        Table.ColumnNames(getProjects),
                        {}
                    ),

            insightsData =
                if processInsights then
                    let
                        polarisData = getPolarisInsights(
                            jpdProjects,
                            cloudId,
                            accessToken
                        )
                    in
                        polarisData
                else
                    [NavigationTable = #table({"ProjectKey"}, {}), ProjectsInsights = []],




           insightsForNav = 
            if processInsights then
                let
                    navTable = insightsData[NavigationTable],
                    projectInsights = insightsData[ProjectsInsights],
                    
                    // Transform each project into a navigation entry
                    entries = Table.TransformRows(
                        navTable,
                        each {
                            [ProjectKey] & " - " & [ProjectName],  // Name shown in navigator
                            Record.Field(projectInsights, [ProjectKey])[InsightsTable],  // The insights table
                            "Table",
                            "Table",
                            true  // IsLeaf
                        }
                    )
                in
                    entries
            else
                {},
            

            //GraphQL Schema Introspection (for development/debugging purposes)
            /*
            JPDSchemaIntrospection = 
                let
                    // Introspection query to discover available fields on the Query type
                    query = "
                        query IntrospectSchema {
                            __schema {
                                queryType {
                                    name
                                    fields {
                                        name
                                        description
                                        args {
                                            name
                                            type {
                                                name
                                                kind
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    ",
                    
                    // No variables needed for introspection
                    response = Web.Contents(
                        "https://api.atlassian.com/graphql?product=jira-product-discovery",
                        [
                            Content = Json.FromValue([query=query]),
                            Headers = [
                                Authorization = "Bearer " & accessToken,
                                Accept = "application/json",
                                #"Content-Type" = "application/json"
                            ],
                            ManualCredentials = true
                        ]
                    ),
                    
                    json = Json.Document(response),
                    
                    // Extract the fields list
                    queryFields = json[data][__schema][queryType][fields],
                    
                    // Convert to table for easy viewing
                    fieldsTable = Table.FromRecords(queryFields)
                in
                    fieldsTable,
            */



            
            issuesForNav = Table.TransformRows(issues, 
                        each {
                            [name],
                            [Issues],                   // Data: The actual issues table
                            "Table",
                            "Table",
                            true
                        }
                    ),
            
            
            baseEntries = {
                {
                    "Issues",
                    createIssuesNavigationTable(issuesForNav),
                    "Folder",
                    "Folder",
                    false
                }
            },

            entriesWithInsights =
                if processInsights and List.Count(insightsForNav) > 0 then
                    List.Combine({
                        baseEntries,
                        {
                            {
                                "Insights",
                                createIssuesNavigationTable(insightsForNav),
                                "Folder",
                                "Folder",
                                false
                            }
                        }
                    })
                else
                    baseEntries,

            entriesWithValidation =
                if projectValidation[HasInvalidKeys] or List.Count(requestedProjects) > 0 then
                    List.Combine({
                        entriesWithInsights,
                        {
                            {
                                "Project Filter Report",
                                projectValidation[Report],
                                "Table",
                                "Table",
                                true
                            }
                        }
                    })
                else
                    baseEntries,
            
            source = Table.FromRows(
                entriesWithValidation,
                {"Name", "Data", "ItemKind", "ItemName", "IsLeaf"}
            ),
            navTable = Table.ToNavigationTable(
                source, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf"
            )
        in
            //deBugCredentials;
            //JPDSchemaIntrospection;
            navTable;