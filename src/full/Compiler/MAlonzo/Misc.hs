module Compiler.MAlonzo.Misc where

import Control.Monad.State
import Data.Generics
import Data.Generics.Aliases
import Data.List as L
import Data.Map as M
import Data.Set as S
import Data.Maybe
import Language.Haskell.Syntax
import System.IO
import System.Time

import Interaction.Imports
import Interaction.Monad
import Syntax.Common
import qualified Syntax.Concrete.Name as C
import Syntax.Internal
import Syntax.Position
import Syntax.Scope.Base
import Syntax.Translation.ConcreteToAbstract
import TypeChecking.Monad
import TypeChecking.Monad.Builtin
import Utils.FileName
import Utils.Function
import Utils.Monad

--------------------------------------------------
-- Setting up Interface before compile
--------------------------------------------------

-- find the abstract module name from the given file name
mnameFromFileName :: IM () -> FilePath -> TCM ModuleName
mnameFromFileName typecheck = (sigMName <$>) .
  (maybe (typecheck>> getSignature) (return . iSignature) =<<) .
  liftIO . readInterface . setExtension ".agdai"

-- the known module name used to find the current interface
mazCurrentMod = "MazCurrentModule"

setInterface :: (Interface, ClockTime) -> TCM ()
setInterface ict = do modify $ \s -> s {stImportedModules = S.empty}
                      (`uncurry` ict) . visitModule =<< mazCurMName

mazCurMName :: TCM ModuleName
mazCurMName = maybe firstTime return .  L.lookup mazCurrentMod .
              L.map (\m -> (show m, m)) . keys =<< getVisitedModules
  where firstTime = concreteToAbstract_ . NewModuleQName . C.QName $
                    C.Name noRange [C.Id noRange mazCurrentMod]

curIF :: TCM Interface
curIF = fst <$> (join $ M.lookup <$> mazCurMName <*> getVisitedModules)

curSig :: TCM Signature
curSig = iSignature <$> curIF

curMName :: TCM ModuleName
curMName = sigMName <$> curSig

curHsMod :: TCM Module
curHsMod = mazMod <$> curMName

curDefs :: TCM Definitions
curDefs = sigDefinitions <$> curSig

sigMName :: Signature -> ModuleName
sigMName = head . M.keys . sigSections

--------------------------------------------------
-- utilities for haskell names
--------------------------------------------------

ihname :: String -> Nat -> HsName
ihname s i = HsIdent $ s ++ show i

unqhname :: String -> QName -> HsName
unqhname s q | ("d", "main") == (s, show(qnameName q)) = HsIdent "main :: IO()"
             | otherwise = ihname s (idnum $ nameId $ qnameName $ q)
  where idnum (NameId x _) = fromIntegral x

-- the toplevel module containing the given one
tlmodOf :: ModuleName -> TCM Module
tlmodOf = fmap mazMod . tlmname

tlmname :: ModuleName -> TCM ModuleName
tlmname m = do
  ms <- sortBy (compare `on` (length . mnameToList)) .
        L.filter (flip (isPrefixOf `on` mnameToList) m) <$>
        ((:) <$> curMName <*> (keys <$> getVisitedModules))
  return $ case ms of (m' : _) -> m'; _ -> mazerror$ "tlmodOf: "++show m

-- qualify HsName n by the module of QName q, if necessary;
-- accumulates the used module in stImportedModules at the same time.
xqual :: QName -> HsName -> TCM HsQName
xqual q n = do m1 <- tlmname (qnameModule q)
               m2 <- curMName
               if m1 == m2 then return (UnQual n)
                  else addImport m1 >> return (Qual (mazMod m1) n)

xhqn :: String -> QName -> TCM HsQName
xhqn s q = xqual q (unqhname s q)

-- always use the original name for a constructor even when it's redefined.
conhqn :: QName -> TCM HsQName
conhqn q = xhqn "C" =<< ignoreAbstractMode (canonicalName q)

-- qualify name s by the module of builtin b
bltQual :: String -> String -> TCM HsQName
bltQual b s = do (Def q _) <- getBuiltin b; xqual q (HsIdent s) 

-- sub-naming for cascaded definitions for concsecutive clauses
dsubname q i | i == 0    = unqhname "d"                     q
             | otherwise = unqhname ("d_" ++ show i ++ "_") q

hsVarUQ :: HsName -> HsExp
hsVarUQ = HsVar . UnQual

--------------------------------------------------
-- Hard coded module names
--------------------------------------------------

mazstr  = "MAlonzo"
mazName = mkName_ dummy mazstr
mazMod' s = Module $ mazstr ++ "." ++ s
mazMod :: ModuleName -> Module
mazMod = mazMod' . show
mazerror msg = error $ mazstr ++ ": " ++ msg
mazCoerce = hsVarUQ $ HsIdent "unsafeCoerce"

-- for Runtime module: Not really used (Runtime modules has been abolished).
rtmMod  = mazMod' "Runtime"
rtmQual = UnQual . HsIdent
rtmVar  = HsVar . rtmQual
rtmError s = rtmVar "error" `HsApp` 
             (HsLit $ HsString $ "MAlonzo Runtime Error: " ++ s)

unsafeCoerceMod = Module "Unsafe.Coerce"

--------------------------------------------------
-- Sloppy ways to declare <name> = <string>
--------------------------------------------------

fakeD :: HsName -> String -> HsDecl
fakeD v s = HsFunBind [HsMatch dummy v []
                      (HsUnGuardedRhs $ hsVarUQ $ HsIdent $ s) [] ]

fakeDS :: String -> String -> HsDecl
fakeDS = fakeD . HsIdent

fakeDQ :: QName -> String -> HsDecl
fakeDQ = fakeD . unqhname "d"

dummy :: a
dummy = error "MAlonzo : this dummy value should not have been eval'ed."
    

--------------------------------------------------
-- For Debugging
--------------------------------------------------
gshow' :: Data a => a -> String
gshow' = ( \t ->
           "("
           ++ showConstr (toConstr t)
           ++ concat (gmapQ ((++) " " . gshow') t)
           ++ ")" )
         `extQ` (show :: String -> String)
         `extQ` (show :: Name -> String)
         `extQ` (show :: QName -> String)
         `extQ` (show :: ModuleName -> String)
         `extQ` (gshow' . M.toList :: M.Map QName [AbstractName] -> String)
         `extQ` (gshow' . M.toList :: M.Map QName [AbstractModule] -> String)
         `extQ` (gshow' . M.toList :: M.Map ModuleName Section -> String)
         `extQ` (gshow' . M.toList :: M.Map QName Definition -> String)
         `extQ` (gshow' . M.toList :: M.Map TermHead [Pattern] -> String)
         `extQ` (gshow' . M.toList :: M.Map TermHead [Arg Pattern] -> String)
         `extQ` (gshow' . M.toList :: M.Map String (Builtin String) -> String)
         `extQ` (show :: Scope -> String)


