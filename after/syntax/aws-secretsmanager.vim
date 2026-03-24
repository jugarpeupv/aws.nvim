" aws.nvim – syntax highlighting for the aws-secretsmanager filetype
syntax clear

" Stop regex matching past column 200 to avoid lag when holding j/k
setlocal synmaxcol=200

" ── Separators ───────────────────────────────────────────────────────────────
syntax match AwsSmSep         /^-\+$/

" ── Titles ───────────────────────────────────────────────────────────────────
syntax match AwsSmTitle       /^Secrets Manager.*/

" ── Filter / loading badges ──────────────────────────────────────────────────
syntax match AwsSmFilter      /\[filter:[^\]]*\]/
syntax match AwsSmLoading     /\[loading[^\]]*\]/

" ── Region / profile badges ──────────────────────────────────────────────────
syntax match AwsSmBadge       /\[region:[^\]]*\]/
syntax match AwsSmBadge       /\[profile:[^\]]*\]/

" ── Section headers ──────────────────────────────────────────────────────────
syntax match AwsSmSection     /^Name\s\+Description.*/
syntax match AwsSmSection     /^Identifiers$/
syntax match AwsSmSection     /^General$/
syntax match AwsSmSection     /^Rotation$/
syntax match AwsSmSection     /^Tags$/
syntax match AwsSmSection     /^Versions$/

" ── Rotation enabled / disabled ───────────────────────────────────────────────
syntax match AwsSmEnabled     /\byes\b/
syntax match AwsSmDisabled    /\bno\b/

" ── Dates (YYYY-MM-DD) ────────────────────────────────────────────────────────
syntax match AwsSmDate        /\d\{4}-\d\{2}-\d\{2}/

" ── ARNs ──────────────────────────────────────────────────────────────────────
syntax match AwsSmArn         /arn:aws[^ ]*/

" ── Version staging labels ────────────────────────────────────────────────────
syntax match AwsSmStage       /AWSCURRENT\|AWSPREVIOUS\|AWSPENDING/

" ── Highlight links ──────────────────────────────────────────────────────────
highlight default link AwsSmSep      Comment
highlight default link AwsSmTitle    Title
highlight default link AwsSmFilter   WarningMsg
highlight default link AwsSmLoading  WarningMsg
highlight default link AwsSmBadge    SpecialComment
highlight default link AwsSmSection  Normal
highlight default link AwsSmEnabled  DiagnosticOk
highlight default link AwsSmDisabled Comment
highlight default link AwsSmDate     Constant
highlight default link AwsSmArn      Comment
highlight default link AwsSmStage    Identifier

let b:current_syntax = "aws-secretsmanager"
