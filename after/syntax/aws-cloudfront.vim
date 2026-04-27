" aws.nvim – syntax highlighting for the aws-cloudfront filetype
syntax clear


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

" ── Section headers (exact anchored matches) ──────────────────────────────────
syntax match AwsCfSection     /^General$/
syntax match AwsCfSection     /^Aliases (CNAMEs)$/
syntax match AwsCfSection     /^Origins$/
syntax match AwsCfSection     /^Default Cache Behaviour$/
syntax match AwsCfSection     /^Cache Behaviours ([0-9]\+)$/
syntax match AwsCfSection     /^SSL \/ Viewer Certificate$/
syntax match AwsCfSection     /^ID\s\+Status.*/

" ── Distribution status ───────────────────────────────────────────────────────
syntax match AwsCfDeployed    /\<Deployed\>/
syntax match AwsCfInProgress  /\<InProgress\>/

" ── Enabled / disabled boolean ───────────────────────────────────────────────
syntax match AwsCfEnabled     /\<true\>/
syntax match AwsCfDisabled    /\<false\>/

" ── Distribution IDs (uppercase alphanumeric, 13–14 chars) ───────────────────
syntax match AwsCfDistId      /\b[A-Z0-9]\{13,14\}\b/

" ── CloudFront domain names ───────────────────────────────────────────────────
syntax match AwsCfDomain      /[a-z0-9\-]\{1,63\}\.cloudfront\.net/

" ── Viewer protocol policy values ────────────────────────────────────────────
syntax match AwsCfProtocol    /\(allow-all\|https-only\|redirect-to-https\)/

" ── Price class values ────────────────────────────────────────────────────────
syntax match AwsCfPriceClass  /PriceClass_[A-Za-z0-9_]\{1,16\}/

" ── Dates (YYYY-MM-DD) ────────────────────────────────────────────────────────
syntax match AwsCfDate        /\d\{4}-\d\{2}-\d\{2}/

" ── ARNs ──────────────────────────────────────────────────────────────────────
syntax match AwsCfArn         /arn:aws[^ ]*/

" ── Highlight links ──────────────────────────────────────────────────────────
highlight default link AwsCfSep        Comment
highlight default link AwsCfTitle      Title
highlight default link AwsCfFilter     WarningMsg
highlight default link AwsCfLoading    WarningMsg
highlight default link AwsCfBadge      SpecialComment
highlight default link AwsCfSection    Statement
highlight default link AwsCfDeployed   DiagnosticOk
highlight default link AwsCfInProgress WarningMsg
highlight default link AwsCfEnabled    DiagnosticOk
highlight default link AwsCfDisabled   Comment
highlight default link AwsCfDistId     Identifier
highlight default link AwsCfDomain     String
highlight default link AwsCfProtocol   Type
highlight default link AwsCfPriceClass Constant
highlight default link AwsCfDate       Constant
highlight default link AwsCfArn        Comment

let b:current_syntax = "aws-cloudfront"
