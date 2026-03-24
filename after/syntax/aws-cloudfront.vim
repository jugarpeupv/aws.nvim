" aws.nvim – syntax highlighting for the aws-cloudfront filetype
syntax clear

" Stop regex matching past column 200 to avoid lag when holding j/k
setlocal synmaxcol=200

" ── Separators ───────────────────────────────────────────────────────────────
syntax match AwsCfSep         /^-\+$/

" ── Titles ───────────────────────────────────────────────────────────────────
syntax match AwsCfTitle       /^CloudFront.*/

" ── Filter / loading badges ──────────────────────────────────────────────────
syntax match AwsCfFilter      /\[filter:[^\]]*\]/
syntax match AwsCfLoading     /\[loading[^\]]*\]/

" ── Region / profile badges ──────────────────────────────────────────────────
syntax match AwsCfBadge       /\[region:[^\]]*\]/
syntax match AwsCfBadge       /\[profile:[^\]]*\]/

" ── Section headers ──────────────────────────────────────────────────────────
syntax match AwsCfSection     /^General$/
syntax match AwsCfSection     /^Aliases (CNAMEs)$/
syntax match AwsCfSection     /^Origins$/
syntax match AwsCfSection     /^Default Cache Behaviour$/
syntax match AwsCfSection     /^Cache Behaviours.*$/
syntax match AwsCfSection     /^SSL \/ Viewer Certificate$/
syntax match AwsCfSection     /^ID\s\+Domain.*/

" ── Status: Enabled / Disabled ────────────────────────────────────────────────
syntax match AwsCfEnabled     /\bDeployed\b/
syntax match AwsCfEnabled     /\bEnabled\b/
syntax match AwsCfDisabled    /\bDisabled\b/
syntax match AwsCfInProgress  /\bIn Progress\b/

" ── Dates (YYYY-MM-DD) ────────────────────────────────────────────────────────
syntax match AwsCfDate        /\d\{4}-\d\{2}-\d\{2}/

" ── ARNs ──────────────────────────────────────────────────────────────────────
syntax match AwsCfArn         /arn:aws[^ ]*/

" ── Distribution IDs (Exxxx uppercase 14-char) ────────────────────────────────
syntax match AwsCfId          /\b[A-Z0-9]\{13,14\}\b/

" ── CloudFront domains ────────────────────────────────────────────────────────
syntax match AwsCfDomain      /[a-z0-9]\+\.cloudfront\.net/

" ── Highlight links ──────────────────────────────────────────────────────────
highlight default link AwsCfSep        Comment
highlight default link AwsCfTitle      Title
highlight default link AwsCfFilter     WarningMsg
highlight default link AwsCfLoading    WarningMsg
highlight default link AwsCfBadge      SpecialComment
highlight default link AwsCfSection    Normal
highlight default link AwsCfEnabled    DiagnosticOk
highlight default link AwsCfDisabled   Comment
highlight default link AwsCfInProgress WarningMsg
highlight default link AwsCfDate       Constant
highlight default link AwsCfArn        Comment
highlight default link AwsCfId         Identifier
highlight default link AwsCfDomain     String

let b:current_syntax = "aws-cloudfront"
