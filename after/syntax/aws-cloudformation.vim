" aws.nvim – syntax highlighting for the aws-cloudformation filetype
syntax clear


" ── Separators ───────────────────────────────────────────────────────────────
syntax match AwsCfSep        /^-\+$/

" ── Title line ───────────────────────────────────────────────────────────────
syntax match AwsCfTitle      /^CloudFormation Stacks/
syntax match AwsCfTitle      /^Events  >>.*$/

" ── Filter / loading badges ──────────────────────────────────────────────────
syntax match AwsCfFilter     /\[filter:[^\]]*\]/
syntax match AwsCfLoading    /\[loading[^\]]*\]/


" ── Status values ─────────────────────────────────────────────────────────────
" Listed individually — no alternation groups, so every pattern is unambiguous.

syntax match AwsCfDeleted    /DELETE_COMPLETE/
syntax match AwsCfDeleted    /DELETE_IN_PROGRESS/
syntax match AwsCfDeleted    /DELETE_FAILED/

syntax match AwsCfFailed     /CREATE_FAILED/
syntax match AwsCfFailed     /ROLLBACK_FAILED/
syntax match AwsCfFailed     /UPDATE_ROLLBACK_FAILED/
syntax match AwsCfFailed     /IMPORT_ROLLBACK_FAILED/

syntax match AwsCfInProgress /CREATE_IN_PROGRESS/
syntax match AwsCfInProgress /ROLLBACK_IN_PROGRESS/
syntax match AwsCfInProgress /UPDATE_IN_PROGRESS/
syntax match AwsCfInProgress /UPDATE_COMPLETE_CLEANUP_IN_PROGRESS/
syntax match AwsCfInProgress /UPDATE_ROLLBACK_IN_PROGRESS/
syntax match AwsCfInProgress /UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS/
syntax match AwsCfInProgress /REVIEW_IN_PROGRESS/
syntax match AwsCfInProgress /IMPORT_IN_PROGRESS/
syntax match AwsCfInProgress /IMPORT_ROLLBACK_IN_PROGRESS/

syntax match AwsCfComplete   /CREATE_COMPLETE/
syntax match AwsCfComplete   /UPDATE_COMPLETE/
syntax match AwsCfComplete   /UPDATE_ROLLBACK_COMPLETE/
syntax match AwsCfComplete   /ROLLBACK_COMPLETE/
syntax match AwsCfComplete   /IMPORT_COMPLETE/
syntax match AwsCfComplete   /IMPORT_ROLLBACK_COMPLETE/

" ── Highlight links ──────────────────────────────────────────────────────────
highlight default link AwsCfSep        Comment
highlight default link AwsCfTitle      Title
highlight default link AwsCfFilter     WarningMsg
highlight default link AwsCfLoading    WarningMsg
highlight default link AwsCfComplete   DiagnosticOk
highlight default link AwsCfInProgress DiagnosticWarn
highlight default link AwsCfFailed     DiagnosticError
highlight default link AwsCfDeleted    Comment

let b:current_syntax = "aws-cloudformation"
