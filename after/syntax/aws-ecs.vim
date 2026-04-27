" aws.nvim – syntax highlighting for the aws-ecs filetype
syntax clear


" ── Separators ───────────────────────────────────────────────────────────────
syntax match AwsEcsSep         /^-\+$/

" ── Titles ───────────────────────────────────────────────────────────────────
syntax match AwsEcsTitle       /^ECS.*/

" ── Filter / loading badges ──────────────────────────────────────────────────
syntax match AwsEcsFilter      /\[filter:[^\]]*\]/
syntax match AwsEcsLoading     /\[loading[^\]]*\]/

" ── Region / profile badges ──────────────────────────────────────────────────
syntax match AwsEcsBadge       /\[region:[^\]]*\]/
syntax match AwsEcsBadge       /\[profile:[^\]]*\]/

" ── Section headers (exact anchored matches) ──────────────────────────────────
syntax match AwsEcsSection     /^Cluster$/
syntax match AwsEcsSection     /^Statistics$/
syntax match AwsEcsSection     /^Services ([0-9]\+)$/
syntax match AwsEcsSection     /^Services$/
syntax match AwsEcsSection     /^Name\s\+Region.*/

" ── Services table column header ─────────────────────────────────────────────
syntax match AwsEcsColHeader   /^\s\+Name\s\+Status\s\+Launch.*/

" ── Cluster / service status ─────────────────────────────────────────────────
syntax match AwsEcsActive      /\<ACTIVE\>/
syntax match AwsEcsDraining    /\<DRAINING\>/
syntax match AwsEcsInactive    /\<INACTIVE\>/

" ── Launch types ─────────────────────────────────────────────────────────────
syntax match AwsEcsLaunch      /\<\(FARGATE\|EC2\|CAP_PROV\)\>/

" ── Deployment status (non-PRIMARY deployments shown inline) ─────────────────
syntax match AwsEcsDepStatus   /deployment \(ACTIVE\|INACTIVE\|FAILED\|COMPLETED\)/

" ── Dates (YYYY-MM-DD) ────────────────────────────────────────────────────────
syntax match AwsEcsDate        /\d\{4}-\d\{2}-\d\{2}/

" ── Event timestamps [HH:MM:SS] ──────────────────────────────────────────────
syntax match AwsEcsTime        /\[\d\{2}:\d\{2}:\d\{2}\]/

" ── ARNs ──────────────────────────────────────────────────────────────────────
syntax match AwsEcsArn         /arn:aws[^ ]*/

" ── Highlight links ──────────────────────────────────────────────────────────
highlight default link AwsEcsSep        Comment
highlight default link AwsEcsTitle      Title
highlight default link AwsEcsFilter     WarningMsg
highlight default link AwsEcsLoading    WarningMsg
highlight default link AwsEcsBadge      SpecialComment
highlight default link AwsEcsSection    Statement
highlight default link AwsEcsColHeader  Normal
highlight default link AwsEcsActive     DiagnosticOk
highlight default link AwsEcsDraining   WarningMsg
highlight default link AwsEcsInactive   Comment
highlight default link AwsEcsLaunch     Identifier
highlight default link AwsEcsDepStatus  WarningMsg
highlight default link AwsEcsDate       Constant
highlight default link AwsEcsTime       Comment
highlight default link AwsEcsArn        Comment

let b:current_syntax = "aws-ecs"
