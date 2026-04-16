" aws.nvim – syntax highlighting for the aws-s3 filetype
syntax clear

" ── Separators ───────────────────────────────────────────────────────────────
syntax match AwsS3Sep       /^-\+$/

" ── Title ────────────────────────────────────────────────────────────────────
syntax match AwsS3Title     /^S3 Buckets.*/

" ── Filter badge ─────────────────────────────────────────────────────────────
syntax match AwsS3Filter    /\[filter:[^\]]*\]/


" ── Column header ────────────────────────────────────────────────────────────
syntax match AwsS3ColHeader /^Name\s\+Created$/

" ── Bucket names (identifier at start of data rows, before the date) ─────────
" Hint-line keys are at most 2-3 chars (dd, de, <CR> etc.).
" Requiring 5+ chars safely excludes them without mandating a separator.
syntax match AwsS3Bucket    /^[a-z0-9][a-z0-9._-]\{4,}/

" ── ISO date column ──────────────────────────────────────────────────────────
syntax match AwsS3Date      /\d\{4}-\d\{2}-\d\{2} \d\{2}:\d\{2}:\d\{2}[+-]\d\{2}:\d\{2}/

" ── Highlight links ──────────────────────────────────────────────────────────
highlight default link AwsS3Sep       Comment
highlight default link AwsS3Title     Title
highlight default link AwsS3Filter    WarningMsg
highlight default link AwsS3ColHeader Normal
highlight default link AwsS3Bucket    Identifier
highlight default link AwsS3Date      Comment

let b:current_syntax = "aws-s3"
