" aws.nvim – syntax highlighting for the aws-iam filetype
syntax clear

" Stop regex matching past column 120 to avoid lag when holding j/k
setlocal synmaxcol=120

" ── Separators ───────────────────────────────────────────────────────────────
syntax match AwsIamSep         /^-\+$/

" ── Title lines ──────────────────────────────────────────────────────────────
syntax match AwsIamTitle       /^IAM\s.*/

" ── Region / profile / scope badges ─────────────────────────────────────────
syntax match AwsIamBadge       /\[region:[^\]]*\]/
syntax match AwsIamBadge       /\[profile:[^\]]*\]/
syntax match AwsIamBadge       /\[scope:[^\]]*\]/

" ── Filter / loading badges ──────────────────────────────────────────────────
syntax match AwsIamFilter      /\[filter:[^\]]*\]/
syntax match AwsIamLoading     /\[loading[^\]]*\]/

" ── Section headers (exact matches for common headers) ───────────────────────
syntax match AwsIamSection     /^General$/
syntax match AwsIamSection     /^Groups$/
syntax match AwsIamSection     /^Members$/
syntax match AwsIamSection     /^Attached Policies$/
syntax match AwsIamSection     /^Inline Policies$/
syntax match AwsIamSection     /^Access Keys$/
syntax match AwsIamSection     /^MFA Devices$/
syntax match AwsIamSection     /^Versions$/
syntax match AwsIamSection     /^Attached To$/
syntax match AwsIamSection     /^Trust Policy (AssumeRole)$/
syntax match AwsIamSection     /^Tags$/
syntax match AwsIamSection     /^Last Accessed$/
syntax match AwsIamSection     /^OIDC Provider$/
syntax match AwsIamSection     /^SAML Provider$/
syntax match AwsIamSection     /^Client IDs$/
syntax match AwsIamSection     /^Thumbprints$/
syntax match AwsIamSection     /^SAML Metadata Document.*$/

" ── Column headers ───────────────────────────────────────────────────────────
syntax match AwsIamSection     /^Name\s\+Created.*/
syntax match AwsIamSection     /^Type\s\+ARN.*/
syntax match AwsIamSection     /^\s*Service\s\+Last Authenticated.*/

" ── JSON keys (quoted strings followed by colon) ─────────────────────────────
syntax match AwsIamJsonKey     /"\([^"]*\)":/

" ── JSON string values (quoted strings NOT followed by colon) ────────────────
syntax match AwsIamJsonStr     /:\s*"\([^"]*\)"/

" ── Menu item numbers ────────────────────────────────────────────────────────
syntax match AwsIamMenuNum     /^\s\+[1-9]\./

" ── Menu resource labels ─────────────────────────────────────────────────────
syntax match AwsIamMenuLabel   /\(Users\|Groups\|Roles\|Policies\|Identity Providers\)/

" ── Access key status ────────────────────────────────────────────────────────
syntax match AwsIamActive      /\<Active\>/
syntax match AwsIamInactive    /\<Inactive\>/

" ── Policy version markers ───────────────────────────────────────────────────
syntax match AwsIamDefault     /\[default\]/

" ── ARNs ─────────────────────────────────────────────────────────────────────
syntax match AwsIamArn         /arn:aws[^ ]*/

" ── Effect: Allow / Deny ─────────────────────────────────────────────────────
syntax match AwsIamAllow       /\<Allow\>/
syntax match AwsIamDeny        /\<Deny\>/

" ── Provider types ───────────────────────────────────────────────────────────
syntax match AwsIamKind        /\<\(OIDC\|SAML\)\>/

" ── Highlight links ──────────────────────────────────────────────────────────
highlight default link AwsIamSep       Comment
highlight default link AwsIamTitle     Title
highlight default link AwsIamBadge     SpecialComment
highlight default link AwsIamFilter    WarningMsg
highlight default link AwsIamLoading   WarningMsg
highlight default link AwsIamSection   Statement
highlight default link AwsIamMenuNum   Number
highlight default link AwsIamMenuLabel Identifier
highlight default link AwsIamActive    String
highlight default link AwsIamInactive  Comment
highlight default link AwsIamDefault   Special
highlight default link AwsIamArn       Comment
highlight default link AwsIamAllow     String
highlight default link AwsIamDeny      ErrorMsg
highlight default link AwsIamKind      Type
highlight default link AwsIamJsonKey   Identifier
highlight default link AwsIamJsonStr   String

let b:current_syntax = "aws-iam"
