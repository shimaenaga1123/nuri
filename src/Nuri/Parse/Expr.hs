module Nuri.Parse.Expr where

import           Prelude                           hiding ( unwords
                                                          , fromList
                                                          )

import           Data.List                                ( foldl1'
                                                          , groupBy
                                                          )
import           Data.List.NonEmpty                       ( fromList )
import           Data.String                              ( unwords )

import qualified Text.Megaparsec               as P
import           Text.Megaparsec                          ( (<?>) )

import qualified Text.Megaparsec.Char          as P
import qualified Text.Megaparsec.Char.Lexer    as L

import           Control.Monad.Combinators.Expr           ( makeExprParser
                                                          , Operator
                                                            ( Prefix
                                                            , InfixL
                                                            )
                                                          )

import           Nuri.Parse
import           Nuri.Expr
import           Nuri.Literal
import           Nuri.Decl

parseDecl :: Parser Decl
parseDecl = parseFuncDecl <|> parseConstDecl

parseFuncDecl :: Parser Decl
parseFuncDecl = do
  pos <- getSourceLine
  L.indentBlock
    scn
    (do
      P.try $ reserved "함수"
      args     <- argList []
      funcName <- parseFuncIdentifier
      symbol ":"
      let parseLine = (Left <$> parseDecl) <|> (Right <$> parseExpr)
      return
        (L.IndentSome
          Nothing
          (return . (FuncDecl pos funcName args) . listToExpr . groupList)
          parseLine
        )
    )
 where
  argList :: [(String, String)] -> Parser [(String, String)]
  argList l = do
    identResult <- P.observing parseIdentifier
    case identResult of
      Left  _     -> return l
      Right ident -> do
        josaPos <- P.getOffset
        josa    <- parseJosa
        sc
        when
          (josa `elem` (snd <$> l))
          (do
            P.setOffset josaPos
            fail "조사는 중복되게 사용할 수 없습니다."
          )
        argList (l ++ [(ident, josa)])

  groupList :: [Either a b] -> NonEmpty (Either a [b])
  groupList l =
    fromList (sequence <$> groupBy (\x y -> isRight x && isRight y) l)

  listToExpr :: NonEmpty (Either Decl [Expr]) -> Expr
  listToExpr (x :| xs) = case x of
    Right expr -> case nonEmpty xs of
      Nothing -> case expr of
        (y : []) -> y
        ys       -> Seq $ fromList ys
      Just l -> (Seq . fromList) (expr ++ [listToExpr l])
    Left decl -> case nonEmpty xs of
      Nothing -> let (_, _, expr) = declToExpr decl in expr
      Just l  -> declToLet decl (listToExpr l)

parseJosa :: Parser String
parseJosa =
  (do
      josa <- P.some hangulSyllable
      return
        (case josa of
          "과" -> "와"
          "를" -> "을"
          j   -> j
        )
    )
    <?> "조사"

parseConstDecl :: Parser Decl
parseConstDecl = do
  pos <- getSourceLine
  P.try $ reserved "상수"
  identifier <- lexeme parseIdentifier
  symbol ":"
  ConstDecl pos identifier <$> parseExpr

parseExpr :: Parser Expr
parseExpr = parseIf <|> parseArithmetic

parseIf :: Parser Expr
parseIf =
  (do
      pos <- getSourceLine
      reserved "만약"
      condExpr <- parseExpr
      scn
      reserved "이라면"
      scn
      thenExpr <- parseExpr
      scn
      reserved "아니라면"
      scn
      If pos condExpr thenExpr <$> parseExpr
    )
    <?> "조건식"

parseArithmetic :: Parser Expr
parseArithmetic = makeExprParser
  (   (   P.try
          (  parseTerm
          <* P.notFollowedBy (void parseTerm <|> void parseFuncIdentifier) -- 후에 조사로 변경
          )
      <|> parseNestedFuncCalls
      )
  <?> "표현식"
  )
  table
 where
  table =
    [ [Prefix $ unaryOp "+" Positive, Prefix $ unaryOp "-" Negative]
    , [ InfixL $ binaryOp "*" Multiply
      , InfixL $ binaryOp "/" Divide
      , InfixL $ binaryOp "%" Mod
      ]
    , [InfixL $ binaryOp "+" Add, InfixL $ binaryOp "-" Subtract]
    , [InfixL $ binaryOp "==" Equal, InfixL $ binaryOp "!=" Inequal]
    , [ InfixL $ binaryOp "<=" LessThanEqual
      , InfixL $ binaryOp ">=" GreaterThanEqual
      , InfixL $ binaryOp "<" LessThan
      , InfixL $ binaryOp ">" GreaterThan
      ]
    ]
  binaryOp opStr op = P.hidden $ do
    pos <- getSourceLine
    BinaryOp pos op <$ L.symbol sc opStr
  unaryOp opStr op = P.hidden $ do
    pos <- getSourceLine
    UnaryOp pos op <$ L.symbol sc opStr

parseNestedFuncCalls :: Parser Expr
parseNestedFuncCalls = do
  calls <- P.sepBy1 (parseFuncCall <?> "함수 호출식") (symbol ",")
  let addArg arg (FuncCall pos func args) =
        FuncCall pos func ((arg, "_") : args)
      addArg _ _ = error "불가능한 상황"
  return $ foldl1' addArg calls

parseFuncCall :: Parser Expr
parseFuncCall = do
  args <- P.many (liftA2 (,) (parseNonLexemeTerm <?> "함수 인수") (parseJosa <* sc))
  pos  <- getSourceLine
  func <- parseFuncIdentifier <?> "함수 이름"
  return $ FuncCall pos (Var pos func) args

parseFuncIdentifier :: Parser String
parseFuncIdentifier = lexeme
  (unwords <$> P.sepEndBy1 (P.try $ P.notFollowedBy keyword *> hangulWord)
                           (P.char ' ')
  )
 where
  keywords =
    ["반환하다", "함수", "없음", "참", "거짓", "만약", "이라면", "아니라면", "반복", "인 동안", "순서대로"]
  keyword    = P.choice $ reserved <$> keywords
  hangulWord = P.some hangulSyllable
    -- if word `elem` keywords then fail "예약어를 함수 이름으로 쓸 수 없습니다." else return word

parseTerm :: Parser Expr
parseTerm = lexeme
  (   parseNoneExpr
  <|> parseBoolExpr
  <|> parseCharExpr
  <|> P.try (parseRealExpr)
  <|> parseIntegerExpr
  <|> parseIdentifierExpr
  <|> parseParens
  )

parseNonLexemeTerm :: Parser Expr
parseNonLexemeTerm =
  parseNoneExpr
    <|> parseBoolExpr
    <|> parseCharExpr
    <|> P.try (parseRealExpr)
    <|> parseIntegerExpr
    <|> parseIdentifierExpr
    <|> parseParens

parseParens :: Parser Expr
parseParens = P.between (symbol "(") (symbol ")") parseExpr

parseIdentifierExpr :: Parser Expr
parseIdentifierExpr = liftA2 Var getSourceLine parseIdentifier

parseIdentifier :: Parser String
parseIdentifier =
  (P.between
      (P.char '[')
      (P.char ']')
      ((++) <$> P.some allowedChars <*> P.many
        (P.char ' ' <|> allowedChars <|> (P.digitChar <?> "숫자"))
      )
    )
    <?> "변수 이름"
 where
  allowedChars = hangulSyllable <|> hangulJamo <|> (P.letterChar <?> "영문")

parseNoneExpr :: Parser Expr
parseNoneExpr = do
  pos <- getSourceLine
  reserved "없음"
  return $ Lit pos LitNone

parseIntegerExpr :: Parser Expr
parseIntegerExpr = do
  pos <- getSourceLine
  val <- zeroNumber <|> parseDecimal
  return $ Lit pos (LitInteger val)
 where
  zeroNumber =
    P.char '0' >> parseHexadecimal <|> parseOctal <|> parseBinary <|> return 0

parseRealExpr :: Parser Expr
parseRealExpr = Lit <$> getSourceLine <*> (LitReal <$> parseReal)

parseCharExpr :: Parser Expr
parseCharExpr = Lit <$> getSourceLine <*> (LitChar <$> parseChar)

parseBoolExpr :: Parser Expr
parseBoolExpr = Lit <$> getSourceLine <*> (LitBool <$> parseBool)

parseBinary :: Parser Int64
parseBinary = P.char' 'b' >> (L.binary <?> "2진수")

parseOctal :: Parser Int64
parseOctal = L.octal <?> "8진수"

parseDecimal :: Parser Int64
parseDecimal = L.decimal <?> "정수"

parseHexadecimal :: Parser Int64
parseHexadecimal = P.char' 'x' >> (L.hexadecimal <?> "16진수")

parseReal :: Parser Double
parseReal = L.float

parseChar :: Parser Char
parseChar =
  (P.between (symbol "\'")
             (symbol "\'")
             (P.notFollowedBy (P.char '\'') *> L.charLiteral)
    )
    <?> "문자"

parseBool :: Parser Bool
parseBool = (True <$ reserved "참") <|> (False <$ reserved "거짓")
