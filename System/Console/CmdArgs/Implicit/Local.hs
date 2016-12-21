
-- | This module takes the result of Capture, and deals with all the local
--   constraints.
module System.Console.CmdArgs.Implicit.Local(
    module IL 
    ) where

import System.Console.CmdArgs.Implicit.Internal.Local as IL (
          local, err, Prog_(..), Builtin_(..), Mode_(..), Flag_(..)
          , Fixup(..), isFlag_, progHelpOutput, progVersionOutput
          , progNumericVersionOutput)


