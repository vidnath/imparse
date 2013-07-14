----------------------------------------------------------------
--
-- Imparse
--
-- Text/Imparse/Compile/Haskell.hs
--   Compilation from an Imparse parser definition to a Haskell
--   implementation of a abstract syntax data type and Parsec
--   parser.
--

----------------------------------------------------------------
-- 

{-# LANGUAGE TemplateHaskell #-}

module Text.Imparse.Compile.Haskell
  where

import Data.Char (toLower)
import Data.String.Utils (join, replace)
import Data.Maybe (catMaybes)
import Data.ByteString.Char8 (unpack)
import Data.FileEmbed (embedFile)
import Control.Compilation.Compile

import Text.Imparse.AbstractSyntax

----------------------------------------------------------------
-- Helper functions.

toLowerFirst :: String -> String
toLowerFirst []     = []
toLowerFirst (c:cs) = toLower c : cs

----------------------------------------------------------------
-- Compilation to abstract syntax data type definition.

toAbstractSyntax :: String -> Parser a -> Compile String ()
toAbstractSyntax prefix p =
  do raw $ "module " ++ prefix ++ ".AbstractSyntax\n"
     raw "  where"
     newlines 2
     toDatatype p
     newline
     raw "--eof"

toDatatype :: Parser a -> Compile String ()
toDatatype (Parser _ _ ps) =
  let production :: Production a -> Compile String ()
      production (Production _ e cs) =
        do raw "data "
           raw e
           raw " = "
           indent
           newline
           raw "  "
           choices $ concat cs
           unindent
           newlines 2

      choices :: [Choice a] -> Compile String ()
      choices cs = case cs of
        [c]  -> 
          do choice c
             newline
             raw "deriving (Show, Eq)"
        c:cs ->
          do choice c 
             newline
             raw "| "
             choices cs

      choice :: Choice a -> Compile String ()
      choice c = case c of
        PrecedenceSeparator -> do nothing
        Choice con _ es -> 
          do con <-
               case con of
                 Nothing  -> do { c <- fresh; return $ "C" ++ c }
                 Just con -> return con
             raw con
             raw " "
             mapM element es
             nothing

      element :: Element a -> Compile String ()
      element e = case e of
        NonTerminal _ entity -> do { raw entity; raw " " }
        Many e _ _           -> do { raw "["; elementNoSp e; raw "] " }
        Indented e           -> element e
        StringLiteral        -> raw "String"
        NaturalLiteral       -> raw "Integer"
        DecimalLiteral       -> raw "Double"
        RegExp _             -> raw "String"
        _                    -> do nothing

      elementNoSp :: Element a -> Compile String ()
      elementNoSp e = case e of
        NonTerminal _ entity -> do { raw entity }
        Many e _ _           -> do { raw "["; element e; raw "]" }
        _                    -> element e

  in do mapM production ps
        nothing

----------------------------------------------------------------
-- Compilation to rich reporting instance declarations.

toRichReport :: String -> Parser a -> Compile String ()
toRichReport prefix p =
  do raw $ "module " ++ prefix ++ ".Report"
     newline
     raw "  where"
     newlines 2
     raw "import qualified Text.RichReports as R"
     newlines 2
     toReportFuns p
     newline
     raw "--eof"

toReportFuns :: Parser a -> Compile String ()
toReportFuns (Parser _ _ ps) =
  let production :: Production a -> Compile String ()
      production (Production _ e cs) =
        do raw $ "instance Report " ++ e ++ " where"
           indent
           newline
           raw "report x = case x of"
           indent
           newline
           choices $ concat cs
           unindent
           unindent
           newline

      choices :: [Choice a] -> Compile String ()
      choices cs = case cs of
        []   -> do nothing
        c:cs -> do { choice c; newline; choices cs }

      choice :: Choice a -> Compile String ()
      choice c = case c of
        PrecedenceSeparator -> do nothing
        Choice con _ es -> 
          do con <-
               case con of
                 Nothing  -> do { c <- fresh; return $ "C" ++ c }
                 Just con -> return con
             
             ves <- return $ [("v" ++ show k, es!!k) | k <- [0..length es-1]]
             raw $ con ++ " " ++ join " " [v | (v,e) <- ves, isData e] ++ " -> "
             raw $ "R.Span [] [] $ [" ++ join ", " (catMaybes $ map element ves) ++ "]"
      
      element :: (String, Element a) -> Maybe String
      element (v,e) = case e of
        NonTerminal _ entity -> Just $ "R.report " ++ v
        Many e' _ _          -> element (v,e')
        Indented e'          -> maybe Nothing (\r -> Just $ "R.BlockIndent [] [] $ [" ++ r ++ "]") $ element (v,e')
        Terminal t           -> Just $ "R.key \"" ++ t ++ "\""
        NewLine              -> Just $ "R.Line [] []"
        StringLiteral        -> Just $ "R.lit " ++ v
        NaturalLiteral       -> Just $ "R.lit " ++ v
        DecimalLiteral       -> Just $ "R.lit " ++ v
        Identifier           -> Just $ "R.var " ++ v
        Constructor          -> Just $ "R.Text " ++ v
        Flag                 -> Just $ "R.Text " ++ v
        RegExp _             -> Just $ "R.Text " ++ v
        _                    -> Nothing

  in do mapM production ps
        nothing

----------------------------------------------------------------
-- Compilation to Parsec parser.

toParsec :: String -> Parser a -> Compile String ()
toParsec prefix p =
  do raw $ "module " ++ prefix ++ ".Parse\n  where\n"
     newline
     raw $ "import " ++ prefix ++ ".AbstractSyntax\n"
     newlines 2
     template <- return $ 
                   replace "\n\n" "\n" $ replace "\r" "" $ 
                   unpack $(embedFile "Text/Imparse/Compile/parsec.template")


     raw template
     newlines 2

     newline
     raw "--eof"

toParsecDefs :: Parser a -> Compile String ()
toParsecDefs (Parser _ _ ps) =
  let production :: Production a -> Compile String ()
      production (Production _ e cs) =
        do raw $ "instance Report " ++ e ++ " where"
           indent
           newline
           raw "report x = case x of"
           indent
           newline
           choices $ concat cs
           unindent
           unindent
           newline

      choices :: [Choice a] -> Compile String ()
      choices cs = case cs of
        []   -> do nothing
        c:cs -> do { choice c; newline; choices cs }

      choice :: Choice a -> Compile String ()
      choice c = case c of
        PrecedenceSeparator -> do nothing
        Choice con _ es -> 
          do con <-
               case con of
                 Nothing  -> do { c <- fresh; return $ "C" ++ c }
                 Just con -> return con
             
             ves <- return $ [("v" ++ show k, es!!k) | k <- [0..length es-1]]
             raw $ con ++ " " ++ join " " [v | (v,e) <- ves, isData e] ++ " -> "
             raw $ "R.Span [] [] $ [" ++ join ", " (catMaybes $ map element ves) ++ "]"
      
      element :: (String, Element a) -> Maybe String
      element (v,e) = case e of
        NonTerminal _ entity -> Just $ "R.report " ++ v
        Many e' _ _          -> element (v,e')
        Indented e'          -> maybe Nothing (\r -> Just $ "R.BlockIndent [] [] $ [" ++ r ++ "]") $ element (v,e')
        Terminal t           -> Just $ "R.key \"" ++ t ++ "\""
        NewLine              -> Just $ "R.Line [] []"
        StringLiteral        -> Just $ "R.lit " ++ v
        NaturalLiteral       -> Just $ "R.lit " ++ v
        DecimalLiteral       -> Just $ "R.lit " ++ v
        Identifier           -> Just $ "R.var " ++ v
        Constructor          -> Just $ "R.Text " ++ v
        Flag                 -> Just $ "R.Text " ++ v
        RegExp _             -> Just $ "R.Text " ++ v
        _                    -> Nothing

  in do mapM production ps
        nothing

--eof
