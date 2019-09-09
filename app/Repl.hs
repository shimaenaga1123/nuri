module Repl where

import           System.IO                                ( hFlush )

import           Control.Lens
import           Control.Lens.TH                          ( )

import qualified Data.Map                      as M
import qualified Data.Set                      as S
import           Data.Text                                ( strip )

import           Text.Megaparsec
import           Text.Megaparsec.Pos

import           Nuri.Eval.Stmt
import           Nuri.Eval.Expr
import           Nuri.Expr
import           Nuri.Eval.Val
import           Nuri.Parse.Stmt
import           Nuri.Parse

data ReplState = ReplState { _prompt :: Text, _replSymbolTable :: SymbolTable, _fileName :: Text }

$(makeLenses ''ReplState)

newtype Repl a = Repl { unRepl :: StateT ReplState IO a }
  deriving (Monad, Functor, Applicative, MonadState ReplState, MonadIO)

intrinsicTable :: SymbolTable
intrinsicTable = M.fromList
  [ ( "보여주다"
    , makeFunc
      pos
      ["값"]
      (do
        result <- evalExpr (Var pos "값")
        putTextLn $ printVal result
        return (Normal Undefined)
      )
    )
  ]
  where pos = initialPos "내장"

evalInput :: Text -> Repl (Maybe (Flow Val))
evalInput input = do
  st <- get
  let ast = evalState
        (runParserT (unParse (parseStmts <* eof))
                    (toString $ view fileName st)
                    input
        )
        S.empty
  case ast of
    Left err ->
      liftIO $ (putTextLn . toText . errorBundlePretty) err >> return Nothing
    Right result -> do
      evalResult <- liftIO
        $ runStmtsEval result (InterpreterState (view replSymbolTable st) False)
      case evalResult of
        Left  evalErr           -> liftIO $ print evalErr >> return Nothing
        Right (finalValue, st') -> do
          modify $ set replSymbolTable (view symbolTable st')
          return $ Just finalValue

repl :: Repl ()
repl = do
  st <- get
  liftIO $ do
    putText (view prompt st)
    hFlush stdout
  line <- strip <$> liftIO getLine
  liftIO $ when (line == ":quit") exitSuccess
  result <- evalInput line
  case result of
    Just val -> liftIO $ print val
    Nothing  -> pass
  repl

runRepl :: Repl a -> ReplState -> IO ()
runRepl f st = void $ runStateT (unRepl f) st
