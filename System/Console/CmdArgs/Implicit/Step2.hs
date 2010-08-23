{-# LANGUAGE RecordWildCards, ViewPatterns, PatternGuards #-}

-- | This module takes the result of Capture, and forms the structure of
--   the arguments. This module supplies the most direct translation of
--   the annotations.
module System.Console.CmdArgs.Implicit.Step2(
    step2,
    Prog2(..), Mode2(..), Flag2(..), Flag2Type(..), Arg2(..)
    ) where

import System.Console.CmdArgs.Implicit.Ann
import System.Console.CmdArgs.Implicit.Read
import System.Console.CmdArgs.Implicit.Step1
import System.Console.CmdArgs.Explicit

import Data.Char
import Data.Generics.Any
import Data.List
import Data.Maybe


data Prog2 a = Prog2
    {prog2Summary :: String
    ,prog2Name :: String
    ,prog2Help :: String
    ,prog2Verbosity :: Bool
    ,prog2ModeDefault :: Maybe Int -- index in to prog2Modes
    ,prog2Modes :: [Mode2 a]
    }

data Mode2 a = Mode2
    {mode2Names :: [Name]
    ,mode2Group :: String
    ,mode2Value :: a
    ,mode2Help :: Help
    ,mode2Suffix :: [String]
    ,mode2Flags :: [Flag2 a]
    ,mode2Args :: [Arg2 a]
    }

data Flag2 a = Flag2
    {flag2Names :: [Name]
    ,flag2Group :: String
    ,flag2Upd :: Flag2Type a
    ,flag2Opt :: Maybe String
    ,flag2FlagHelp :: FlagHelp
    ,flag2Help :: Help
    }

data Flag2Type a
    = Flag2String {fromFlag2String :: String -> a -> Either String a}
    | Flag2Bool (Bool -> a -> a)
    | Flag2Value (a -> a)

data Arg2 a = Arg2
    {arg2FlagHelp :: FlagHelp
    ,arg2Upd :: String -> a -> Either String a
    ,arg2Pos :: Maybe Int
    ,arg2Opt :: Maybe String
    }


step2 :: Prog1 -> Prog2 Any
step2 = transProg


isArg FlagArgs = True
isArg FlagArgPos{} = True
isArg _ = False


---------------------------------------------------------------------
-- TRANSLATE
-- Translate in to the Mode domain

transProg :: Prog1 -> Prog2 Any
transProg (Prog1 ann xs) = Prog2 summary program hlp verb defMode (map transMode xs)
    where
        summary = let x = concat [x | ProgSummary x <- ann] in if null x then "The " ++ defProg ++ " program" else x
        hlp = concat [x | Help x <- ann]
        defMode = flip findIndex xs $ \(Mode1 an _ _) -> length xs /= 1 && ModeDefault `elem` an
        verb = ProgVerbosity `elem` ann
        program = last $ defProg : [x | ProgProgram x <- ann]
        defProg = let Mode1 _ x _ = head xs in map toLower $ typeShell x


transMode :: Mode1 -> Mode2 Any
transMode (Mode1 an c xs) = Mode2
    [x | Name x <- an]
    (last $ "" : [x | GroupName x <- an])
    c
    (concat [x | Help x <- an])
    (concat [x | ModeHelpSuffix x <- an])
    (map transFlag rest)
    (map transArg args)
    where (args,rest) = partition (ann isArg) xs
          ann f (Flag1 x _ _) = any f x


transFlag :: Flag1 -> Flag2 Any
transFlag flag@(Flag1 ann fld val)
    | Just (flaghelpdef,upd) <- transFlagType flag =
        Flag2 names grp upd opt (if null flaghelp then flaghelpdef else flaghelp) help
    | otherwise = error $ "Don't know how to deal with field type, " ++ fld ++ " :: " ++ show val
    where
        opt = let a = [x | FlagOptional x <- ann] in if null a then Nothing else Just $ concat a
        grp = last $ "" : [x | GroupName x <- ann]
        help = concat [x | Help x <- ann] ++ concat [" (default=" ++ x ++ ")" | Just x <- [opt], x /= ""]
        names = [x | Name x <- ann]
        flaghelp = concat [x | FlagType x <- ann]


transFlagType :: Flag1 -> Maybe (String,Flag2Type Any)
transFlagType (Flag1 ann fld val)
    | FlagEnum `elem` ann = Just $ (,) "" $ Flag2Value $ \x -> setField (fld,val) x
    | isNothing mty = Nothing
    | isReadBool ty = f $ Flag2Bool $ \b x -> setField (fld,addContainer ty (getField fld x) (Any b)) x
    | otherwise = f $ Flag2String $ \s x -> fmap (\c -> setField (fld,c) x) $ reader ty s $ getField fld x
    where
        mty = toReadContainer val
        ty = fromJust mty
        f x = Just (readHelp ty, x)


transArg :: Flag1 -> Arg2 Any
transArg x@(Flag1 ann _ _) = Arg2 (flag2FlagHelp y) (fromFlag2String $ flag2Upd y) pos (flag2Opt y)
    where y = transFlag x
          pos = listToMaybe [i | FlagArgPos i <- ann]