module Nuri.Parse.Stmt where

import           Control.Monad.Combinators.NonEmpty       ( some )

import           Nuri.Parse
import           Nuri.Parse.Expr
import           Nuri.Stmt

parseStmts :: Parser (NonEmpty Stmt)
parseStmts = some (parseStmt <* scn)

parseStmt :: Parser Stmt
parseStmt = parseDeclStmt <|> parseExprStmt

parseDeclStmt :: Parser Stmt
parseDeclStmt = DeclStmt <$> parseDecl

parseExprStmt :: Parser Stmt
parseExprStmt = ExprStmt <$> parseExpr
