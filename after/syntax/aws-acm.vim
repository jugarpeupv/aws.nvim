" aws.nvim – syntax highlighting for the aws-acm filetype
syntax clear

" Stop regex matching past column 120 to avoid lag when holding j/k
setlocal synmaxcol=120

" ── Separators ───────────────────────────────────────────────────────────────
syntax match AwsAcmSep         /^-\+$/

" ── Titles ───────────────────────────────────────────────────────────────────
syntax match AwsAcmTitle       /^ACM Certificates.*/
syntax match AwsAcmTitle       /^ACM  >>.*$/

" ── Filter / loading badges ──────────────────────────────────────────────────
syntax match AwsAcmFilter      /\[filter:[^\]]*\]/
syntax match AwsAcmLoading     /\[loading[^\]]*\]/

" ── Region / profile badges ──────────────────────────────────────────────────
syntax match AwsAcmBadge       /\[region:[^\]]*\]/
syntax match AwsAcmBadge       /\[profile:[^\]]*\]/

" ── Section headers ──────────────────────────────────────────────────────────
syntax match AwsAcmSection     /^Domain\s\+Status.*/
syntax match AwsAcmSection     /^Identifiers$/
syntax match AwsAcmSection     /^General$/
syntax match AwsAcmSection     /^Certificate Details$/
syntax match AwsAcmSection     /^Subject Alternative Names$/
syntax match AwsAcmSection     /^Domain Validation$/
syntax match AwsAcmSection     /^In Use By$/

" ── Status: ISSUED ────────────────────────────────────────────────────────────
syntax match AwsAcmIssued      /\(ISSUED\)/

" ── Status: PENDING_VALIDATION ────────────────────────────────────────────────
syntax match AwsAcmPending     /\(PENDING_VALIDATION\)/

" ── Status: terminal bad states ───────────────────────────────────────────────
syntax match AwsAcmFailed      /\(EXPIRED\|REVOKED\|FAILED\)/

" ── Status: other ─────────────────────────────────────────────────────────────
syntax match AwsAcmInactive    /\(INACTIVE\|VALIDATION_TIMED_OUT\)/

" ── Certificate type ──────────────────────────────────────────────────────────
syntax match AwsAcmType        /\(AMAZON_ISSUED\|IMPORTED\|PRIVATE\)/

" ── Dates (YYYY-MM-DD) ────────────────────────────────────────────────────────
syntax match AwsAcmDate        /\d\{4}-\d\{2}-\d\{2}/

" ── ARNs ──────────────────────────────────────────────────────────────────────
syntax match AwsAcmArn         /arn:aws[^ ]*/

" ── DNS CNAME records (long strings with dots) ────────────────────────────────
syntax match AwsAcmCname       /\([A-Za-z0-9_\-]\+\.\)\{3,}[A-Za-z0-9_\-]*/

" ── Highlight links ──────────────────────────────────────────────────────────
highlight default link AwsAcmSep       Comment
highlight default link AwsAcmTitle     Title
highlight default link AwsAcmFilter    WarningMsg
highlight default link AwsAcmLoading   WarningMsg
highlight default link AwsAcmBadge     SpecialComment
highlight default link AwsAcmSection   Normal
highlight default link AwsAcmIssued    DiagnosticOk
highlight default link AwsAcmPending   WarningMsg
highlight default link AwsAcmFailed    DiagnosticError
highlight default link AwsAcmInactive  Comment
highlight default link AwsAcmType      Identifier
highlight default link AwsAcmDate      Constant
highlight default link AwsAcmArn       Comment
highlight default link AwsAcmCname     String

let b:current_syntax = "aws-acm"
