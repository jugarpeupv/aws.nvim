" aws.nvim – syntax highlighting for the aws-dynamodb filetype
syntax clear

" Stop regex matching past column 120 to avoid lag when holding j/k
setlocal synmaxcol=120

" ── Separators ───────────────────────────────────────────────────────────────
syntax match AwsDdbSep           /^-\+$/

" ── Title lines ──────────────────────────────────────────────────────────────
syntax match AwsDdbTitle         /^DynamoDB\s.*/

" ── Region / profile badges ──────────────────────────────────────────────────
syntax match AwsDdbBadge         /\[region:[^\]]*\]/
syntax match AwsDdbBadge         /\[profile:[^\]]*\]/

" ── Filter / loading badges ──────────────────────────────────────────────────
syntax match AwsDdbFilter        /\[filter:[^\]]*\]/
syntax match AwsDdbLoading       /\[loading[^\]]*\]/

" ── Pagination badge ─────────────────────────────────────────────────────────
syntax match AwsDdbPager         /\[more pages available\]/

" ── Menu entry lines  (  N.  Label                    Description …)  ─────────
syntax region AwsDdbMenuLine
      \ start=/^\s\+\d\+\.\s/
      \ end=/$/
      \ keepend oneline
      \ contains=AwsDdbMenuNum,AwsDdbMenuLabel,AwsDdbMenuDesc

syntax match AwsDdbMenuNum   /^\s\+\d\+\.\s\+/                       contained
syntax match AwsDdbMenuLabel /[A-Za-z][A-Za-z /]\+\ze\s\{2,}/        contained
syntax match AwsDdbMenuDesc  /\S.*$/                                   contained

" ── Table status keywords (excluded from menu lines) ─────────────────────────
syntax match AwsDdbActive        /\<ACTIVE\>/       containedin=ALLBUT,AwsDdbMenuLine,AwsDdbMenuDesc
syntax match AwsDdbCreating      /\<CREATING\>/     containedin=ALLBUT,AwsDdbMenuLine,AwsDdbMenuDesc
syntax match AwsDdbUpdating      /\<UPDATING\>/     containedin=ALLBUT,AwsDdbMenuLine,AwsDdbMenuDesc
syntax match AwsDdbDeleting      /\<DELETING\>/     containedin=ALLBUT,AwsDdbMenuLine,AwsDdbMenuDesc
syntax match AwsDdbInaccessible  /\<INACCESSIBLE_ENCRYPTION_CREDENTIALS\>/

" ── Billing mode ─────────────────────────────────────────────────────────────
syntax match AwsDdbBilling       /\<\(PAY_PER_REQUEST\|PROVISIONED\)\>/

" ── Table class ──────────────────────────────────────────────────────────────
syntax match AwsDdbClass         /\<\(STANDARD\|STD_IA\|STANDARD_INFREQUENT_ACCESS\)\>/

" ── Section headers ──────────────────────────────────────────────────────────
syntax match AwsDdbSection       /^General$/
syntax match AwsDdbSection       /^Primary Key$/
syntax match AwsDdbSection       /^Attribute Definitions$/
syntax match AwsDdbSection       /^Global Secondary Indexes\s*(.*)/
syntax match AwsDdbSection       /^Local Secondary Indexes\s*(.*)/
syntax match AwsDdbSection       /^DynamoDB Streams$/
syntax match AwsDdbSection       /^Point-in-Time Recovery$/
syntax match AwsDdbSection       /^Tags$/
syntax match AwsDdbSection       /^Items\s*(.*)/

" ── Key type annotations ─────────────────────────────────────────────────────
syntax match AwsDdbKeyType       /\<\(HASH\|RANGE\)\>/

" ── Attribute type annotations ───────────────────────────────────────────────
syntax match AwsDdbAttrType      /\<\(String\|Number\|Binary\)\>/
syntax match AwsDdbAttrTypeCode  /(\(S\|N\|B\), \(HASH\|RANGE\))/

" ── Projection types ─────────────────────────────────────────────────────────
syntax match AwsDdbProjection    /\<\(ALL\|KEYS_ONLY\|INCLUDE\)\>/

" ── Stream view types ────────────────────────────────────────────────────────
syntax match AwsDdbStreamView    /\<\(NEW_IMAGE\|OLD_IMAGE\|NEW_AND_OLD_IMAGES\|KEYS_ONLY\)\>/

" ── Item separator lines ─────────────────────────────────────────────────────
syntax match AwsDdbItemSep       /^\s*── item \d\+ ──$/

" ── ARNs ─────────────────────────────────────────────────────────────────────
syntax match AwsDdbArn           /arn:aws[^ ]*/

" ── NULL / true / false values ───────────────────────────────────────────────
syntax match AwsDdbNull          /\<NULL\>/
syntax match AwsDdbBool          /\<\(true\|false\)\>/

" ── Highlight links ──────────────────────────────────────────────────────────
highlight default link AwsDdbSep          Comment
highlight default link AwsDdbTitle        Title
highlight default link AwsDdbBadge        SpecialComment
highlight default link AwsDdbFilter       WarningMsg
highlight default link AwsDdbLoading      WarningMsg
highlight default link AwsDdbPager        WarningMsg
highlight default link AwsDdbActive       DiagnosticOk
highlight default link AwsDdbCreating     DiagnosticInfo
highlight default link AwsDdbUpdating     DiagnosticInfo
highlight default link AwsDdbDeleting     WarningMsg
highlight default link AwsDdbInaccessible DiagnosticError
highlight default link AwsDdbBilling      Type
highlight default link AwsDdbClass        Type
highlight default link AwsDdbSection      Statement
highlight default link AwsDdbKeyType      Special
highlight default link AwsDdbAttrType     Type
highlight default link AwsDdbAttrTypeCode Comment
highlight default link AwsDdbProjection   Identifier
highlight default link AwsDdbStreamView   Identifier
highlight default link AwsDdbItemSep      Comment
highlight default link AwsDdbArn          Comment
highlight default link AwsDdbNull         Comment
highlight default link AwsDdbBool         String
highlight default link AwsDdbMenuLine     Normal
highlight default link AwsDdbMenuNum      Comment
highlight default link AwsDdbMenuLabel    Function
highlight default link AwsDdbMenuDesc     Comment

let b:current_syntax = "aws-dynamodb"
