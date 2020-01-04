module Haneul.Instruction where

import qualified Data.List.NonEmpty            as NE

import           Control.Lens                             ( makeLenses
                                                          , view
                                                          )

import           Text.Megaparsec.Pos                      ( Pos )

data Instruction = Push Int {- 상수 테이블 인덱스 -} | Pop
                 | Store Int {- 변수 테이블 인덱스 -} | Load Int {- 변수 테이블 인덱스 -}
                 | Call Int {- 인수의 개수 -}
                 | JmpForward Int {- 주소 오프셋 -}
                 | PopJmpIfFalse Int {- 주소 오프셋 -}
                 | Return
                 | Add | Subtract | Multiply | Divide | Mod
                 | Equal | LessThan | GreaterThan
                 | Negate
                 deriving (Eq, Show, Ord)

data AnnInstruction = AnnInst { _lineNumber :: Pos, _instruction :: Instruction }
  deriving (Eq, Show, Ord)

$(makeLenses ''AnnInstruction)

type Code = [AnnInstruction]

opcodeSize :: Int
opcodeSize = 1

operandSize :: Int
operandSize = 3

getInstSize :: Instruction -> Int
getInstSize (Push          _) = opcodeSize + operandSize
getInstSize (Store         _) = opcodeSize + operandSize
getInstSize (Load          _) = opcodeSize + operandSize
getInstSize (Call          _) = opcodeSize + operandSize
getInstSize (JmpForward    _) = opcodeSize + operandSize
getInstSize (PopJmpIfFalse _) = opcodeSize + operandSize
getInstSize (_              ) = opcodeSize

getCodeSize :: Code -> Int
getCodeSize code = sum $ (getInstSize . view instruction) <$> code

prependInst :: Pos -> Instruction -> Code -> Code
prependInst defaultPos inst [] = [AnnInst defaultPos inst]
prependInst _ inst code =
  code ++ [AnnInst (view lineNumber $ last (NE.fromList code)) inst]
