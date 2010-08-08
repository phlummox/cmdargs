
module System.Console.CmdArgs.Explicit.Type where

import Control.Arrow
import Control.Monad
import Data.Char
import Data.List
import Data.Maybe
import Data.Monoid


-- | A name, either the name of a flag (@--/foo/@) or the name of a mode.
type Name = String

-- | A help message that goes with either a flag or a mode.
type Help = String

-- | The type of a flag, i.e. @--foo=/TYPE/@.
type FlagHelp = String


---------------------------------------------------------------------
-- GROUPS

-- | A group of items (modes or flags). The items are treated as a list, but the
--   group structure is used when displaying the help message.
data Group a = Group
    {groupUnnamed :: [a] -- ^ Normal items.
    ,groupHiden :: [a] -- ^ Items that are hidden (not displayed in the help message).
    ,groupNamed :: [(Help, [a])] -- ^ Items that have been grouped, along with a description of each group.
    } deriving Show 

instance Functor Group where
    fmap f (Group a b c) = Group (map f a) (map f b) (map (second $ map f) c)

instance Monoid (Group a) where
    mempty = Group [] [] []
    mappend (Group x1 x2 x3) (Group y1 y2 y3) = Group (x1++y1) (x2++y2) (x3++y3)

-- | Convert a group into a list.
fromGroup :: Group a -> [a]
fromGroup (Group x y z) = x ++ y ++ concatMap snd z

-- | Convert a list into a group, placing all fields in 'groupUnnamed'.
toGroup :: [a] -> Group a
toGroup x = Group x [] []


---------------------------------------------------------------------
-- TYPES

-- | A mode. Each mode has three main features:
--
--   * A list of submodes ('modeGroupModes')
--
--   * A list of flags ('modeGroupFlags')
--
--   * Optionally an unnamed argument ('modeArgs')
data Mode a = Mode
    {modeGroupModes :: Group (Mode a) -- ^ The available sub-modes
    ,modeNames :: [Name] -- ^ The names assigned to this mode
    ,modeValue :: a -- ^ Value to start with
    ,modeCheck :: a -> Either String a -- checking a value is correct
    ,modeHelp :: Help -- ^ Help text
    ,modeHelpSuffix :: [String] -- ^ A longer help suffix displayed after a mode
    ,modeArgs :: Maybe (Arg a) -- ^ An unnamed argument
    ,modeGroupFlags :: Group (Flag a) -- ^ Groups of flags
    }

-- | Extract the modes from a 'Mode'
modeModes :: Mode a -> [Mode a]
modeModes = fromGroup . modeGroupModes

-- | Extract the flags from a 'Mode'
modeFlags :: Mode a -> [Flag a]
modeFlags = fromGroup . modeGroupFlags

-- | The 'FlagInfo' type has the following meaning:
--
--
-- >              FlagReq     FlagOpt      FlagOptRare/FlagNone
-- > -xfoo        -x=foo      -x=foo       -x= -foo
-- > -x foo       -x=foo      -x foo       -x= foo
-- > -x=foo       -x=foo      -x=foo       -x=foo
-- > --xx foo     --xx=foo    --xx foo     --xx foo
-- > --xx=foo     --xx=foo    --xx=foo     --xx=foo
data FlagInfo
    = FlagReq             -- ^ Required argument
    | FlagOpt String      -- ^ Optional argument
    | FlagOptRare String  -- ^ Optional argument that requires an = before the value
    | FlagNone            -- ^ No argument
      deriving (Eq,Ord)

-- | Extract the value from inside a 'FlagOpt' or 'FlagOptRare', or raises an error.
fromFlagOpt :: FlagInfo -> String
fromFlagOpt (FlagOpt x) = x
fromFlagOpt (FlagOptRare x) = x

-- | A function to take a string, and a value, and either produce an error message
--   (@Left@), or a modified value (@Right@).
type Update a = String -> a -> Either String a

-- | A flag, consisting of a list of flag names and other information.
data Flag a = Flag
    {flagNames :: [Name] -- ^ The names for the flag.
    ,flagInfo :: FlagInfo -- ^ Information about a flag's arguments.
    ,flagValue :: Update a -- ^ The way of processing a flag.
    ,flagType :: FlagHelp -- ^ The type of data for the flag argument, i.e. FILE\/DIR\/EXT
    ,flagHelp :: Help -- ^ The help message associated with this flag.
    }

-- | An unnamed argument.
data Arg a = Arg
    {argValue :: Update a -- ^ A way of processing the argument.
    ,argType :: FlagHelp -- ^ The type of data for the argument, i.e. FILE\/DIR\/EXT
    }

---------------------------------------------------------------------
-- CHECK FLAGS

-- | Check that a mode is well formed.
checkMode :: Mode a -> Maybe String
checkMode x =
    (checkNames "modes" $ concatMap modeNames $ modeModes x) `mplus`
    msum (map checkMode $ modeModes x) `mplus`
    (checkGroup $ modeGroupModes x) `mplus`
    (checkGroup $ modeGroupFlags x) `mplus`
    (checkNames "flag names" $ concatMap flagNames $ modeFlags x)
    where
        checkGroup :: Group a -> Maybe String
        checkGroup x =
            (check "Empty group name" $ all (not . null . fst) $ groupNamed x) `mplus`
            (check "Empty group contents" $ all (not . null . snd) $ groupNamed x)

        checkNames :: String -> [Name] -> Maybe String
        checkNames msg xs = check "Empty names" (all (not . null) xs) `mplus` do
            bad <- listToMaybe $ xs \\ nub xs
            let dupe = filter (== bad) xs
            return $ "Sanity check failed, multiple " ++ msg ++ ": " ++ unwords (map show dupe)

        check :: String -> Bool -> Maybe String
        check msg True = Nothing
        check msg False = Just msg


---------------------------------------------------------------------
-- MODE/MODES CREATORS

-- | Create a mode with a name, an initial value, some help text, a way of processing arguments
--   and a list of flags.
mode :: Name -> a -> Help -> Arg a -> [Flag a] -> Mode a
mode name value help arg flags = Mode (toGroup []) [name] value Right help [] (Just arg) $ toGroup flags

-- | Create a list of modes, with an initial value, some help text and the child modes.
modes :: a -> Help -> [Mode a] -> Mode a
modes value help xs = Mode (toGroup xs) [] value Right help [] Nothing $ toGroup []


---------------------------------------------------------------------
-- FLAG CREATORS

-- | Create a flag taking no argument value, with a list of flag names, an update function
--   and some help text.
flagNone :: [Name] -> (a -> a) -> Help -> Flag a
flagNone names f help = Flag names FlagNone upd "" help
    where upd _ x = Right $ f x

-- | Create a flag taking an optional argument value, with an optional value, a list of flag names,
--   an update function, the type of the argument and some help text.
flagOpt :: String -> [Name] -> Update a -> FlagHelp -> Help -> Flag a
flagOpt def names upd typ help = Flag names (FlagOpt def) upd typ help

-- | Create a flag taking a required argument value, with a list of flag names,
--   an update function, the type of the argument and some help text.
flagReq :: [Name] -> Update a -> FlagHelp -> Help -> Flag a
flagReq names upd typ help = Flag names FlagReq upd typ help

-- | Create an argument flag, with an update function and the type of the argument.
flagArg :: Update a -> FlagHelp -> Arg a
flagArg upd typ = Arg upd typ

-- | Create a boolean flag, with a list of flag names, an update function and some help text.
flagBool :: [Name] -> (Bool -> a -> a) -> Help -> Flag a
flagBool names f help = Flag names (FlagOptRare "") upd "" help
    where
        upd s x = if s == "" || ls `elem` boolTrue then Right $ f True x
                  else if ls `elem` boolFalse then Right $ f False x
                  else Left "expected boolean value (true/false)"
            where ls = map toLower s
        boolTrue = ["true","yes","on","enabled","1"]
        boolFalse = ["false","no","off","disabled","0"]
