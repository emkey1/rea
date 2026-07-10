#ifndef REA_PARSER_H
#define REA_PARSER_H

#include "rea/lexer.h"
#include "ast/ast.h"

AST *parseRea(const char *source);
void reaSetStrictMode(int enable);

/* Rewrites AST_VAR_DECL (and array-of-class) type references that were left
 * as bare AST_TYPE_REFERENCE/TYPE_UNKNOWN at parse time into the pointer
 * shape once their name resolves to a class/record in the type table.
 * parseRea() calls this once for same-file forward-declared classes; the
 * semantic analyzer calls it again after module imports load, since an
 * imported class's type isn't registered until then. Safe to call repeatedly:
 * refs that already resolved (or still don't) are left untouched. */
void reaResolveForwardClassRefs(AST *node);

#endif
