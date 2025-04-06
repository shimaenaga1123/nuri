module Nuri.Spec.Parse.Util where

import Data.Map (union)
import Nuri.Expr
import Nuri.Parse
import Nuri.Parse.PartTable
import Test.Hspec (expectationFailure, shouldBe)
import qualified Test.Hspec.Megaparsec as P
import Text.Megaparsec
import Text.Megaparsec.Stream (VisualStream, TraversableStream)

defaultState :: PartTable
defaultState =
  fromList
    [ ("더하다", Verb),
      ("합하다", Verb),
      ("실행하다", Verb),
      ("나누다", Verb),
      ("피보나치 수 구하다", Verb),
      ("같다", Adjective),
      ("크다", Adjective),
      ("던지다", Verb),
      ("받다", Verb)
    ]

testParse :: ParsecT Void Text (StateT PartTable IO) a -> Text -> IO (Either (ParseErrorBundle Text Void) a)
testParse parser input = fst <$> runStateT (runParserT (scn *> parser <* scn <* eof) "(test)" input) defaultState

testParse' :: ParsecT Void Text (StateT PartTable IO) a -> Text -> IO (Either (ParseErrorBundle Text Void) a, PartTable)
testParse' parser input = runStateT (runParserT (scn *> parser <* scn <* eof) "(test)" input) defaultState

shouldParse :: (ShowErrorComponent e, VisualStream s, TraversableStream s, Stream s, Show a, Eq a) => IO (Either (ParseErrorBundle s e) a) -> a -> IO ()
shouldParse p e = do
  r <- p
  r `P.shouldParse` e

shouldParse' ::
  (ShowErrorComponent e, VisualStream s, TraversableStream s, Stream s, Show a, Eq a) =>
  IO (Either (ParseErrorBundle s e) a, PartTable) ->
  (a, PartTable) ->
  IO ()
shouldParse' p (er, et) = do
  (r, t) <- p
  r `P.shouldParse` er
  t `shouldBe` union defaultState et

shouldFailOn :: (t -> IO (Either a b)) -> t -> IO ()
shouldFailOn p e = do
  r <- p e
  case r of
    Left _ -> pass
    Right _ -> expectationFailure "this parser should fail, but succeeded"
