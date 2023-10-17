module Web.UI.Types where

import Data.Aeson
import Data.Map (Map)
import Data.Map.Strict qualified as M
import Data.String (IsString (..))
import Data.Text (Text, pack, unpack)
import Data.Text qualified as T
import Effectful
import Effectful.Reader.Static
import Effectful.State.Static.Local as ES
import GHC.Generics


-- import Data.Text.Lazy qualified as L

type Name = Text
type AttValue = Text


type Attribute = (Name, AttValue)
type Attributes = Map Name AttValue


data Class = Class
  { className :: ClassName
  , classProperties :: Map Name StyleValue
  }


instance ToJSON Class where
  toJSON c = toJSON c.className


className :: Class -> Text
className c = classNameText c.className


classNameSelector :: ClassName -> Text
classNameSelector (ClassName Nothing n) = n
classNameSelector (ClassName ps n) =
  pseudoText ps <> "\\:" <> n <> ":" <> pseudoText ps


-- prefixedName :: Maybe Text -> Text -> Text
-- prefixedName Nothing t = t
-- prefixedName (Just p) t = p <> "." <> t

classNameText :: ClassName -> Text
classNameText (ClassName Nothing n) = n
classNameText (ClassName ps n) =
  pseudoText ps <> ":" <> n


pseudoText :: Maybe Pseudo -> Text
pseudoText Nothing = ""
pseudoText (Just p) = T.toLower $ pack $ show p


data ClassName = ClassName
  { pseudo :: Maybe Pseudo
  , -- , prefix :: Maybe Text
    name :: Text
  }
  deriving (Eq)


instance IsString ClassName where
  fromString s = ClassName Nothing (pack s)


instance Ord ClassName where
  compare a b = compare (classNameText a) (classNameText b)


instance ToJSON ClassName where
  toJSON a = String (classNameText a)


data Pseudo
  = Hover
  | Active
  deriving (Show, Eq)


data StyleValue
  = Px Int
  | Rem Float
  | Hex HexColor
  | RGB String
  | Value String


instance IsString StyleValue where
  fromString = Value


instance Show StyleValue where
  show (Value s) = s
  show (Px n) = show n <> "px"
  show (Rem s) = show s <> "rem"
  show (Hex (HexColor s)) = "#" <> unpack (T.dropWhile (== '#') s)
  -- it needs to have a string?
  -- this might need to get more complicated
  show (RGB s) = "rgb(" <> s <> ")"


newtype HexColor = HexColor Text


instance IsString HexColor where
  fromString = HexColor . T.dropWhile (== '#') . T.pack


attribute :: Name -> AttValue -> Attribute
attribute n v = (n, v)


data Element = Element
  { name :: Name
  , classes :: [[Class]]
  , attributes :: Attributes
  , children :: [Content]
  }


-- optimized for size, [name, atts, [children]]
instance ToJSON Element where
  toJSON el =
    Array
      [ String el.name
      , toJSON $ flatAttributes el
      , toJSON el.children
      ]


data Content
  = Node Element
  | Text Text


instance ToJSON Content where
  toJSON (Node el) = toJSON el
  toJSON (Text t) = String t


{- | Views contain their contents, and a list of all styles mentioned during their rendering
newtype View a = View (State ViewState a)
  deriving newtype (Functor, Applicative, Monad, MonadState ViewState)
-}
data ViewState = ViewState
  { contents :: [Content]
  , classStyles :: ClassStyles
  }


instance Semigroup ViewState where
  va <> vb = ViewState (va.contents <> vb.contents) (va.classStyles <> vb.classStyles)


type ClassStyles = Map ClassName (Map Name StyleValue)


newtype View ctx a = View {viewState :: Eff [Reader ctx, State ViewState] a}
  deriving newtype (Functor, Applicative, Monad)


instance IsString (View ctx ()) where
  fromString s = modContents (const [Text (pack s)])


runView :: ctx -> View ctx () -> ViewState
runView ctx (View ef) =
  runPureEff . execState (ViewState [] []) . runReader ctx $ ef


-- | A function that modifies an element. Allows for easy chaining and composition
type Mod = Element -> Element


modContents :: ([Content] -> [Content]) -> View c ()
modContents f = View $ do
  ES.modify $ \s -> s{contents = f s.contents}


modStyles :: (ClassStyles -> ClassStyles) -> View c ()
modStyles f = View $ do
  ES.modify $ \s -> s{classStyles = f s.classStyles}


context :: View c c
context = View ask


-- we want to convert an existing view to a new context, discarding the old one
addContext :: cx -> View cx () -> View c ()
addContext ctx vw = do
  -- runs the sub-view in a different context, saving its state
  -- we need to MERGE it
  let st = runView ctx vw
  View $ ES.modify $ \s -> s <> st


mapRoot :: Mod -> View c ()
mapRoot f = modContents mapContents
 where
  mapContents (Node root : cts) = Node (f root) : cts
  mapContents cts = cts


data TRBL a = TRBL
  { top :: a
  , right :: a
  , bottom :: a
  , left :: a
  }


-- | Attributes that include classes
newtype FlatAttributes = FlatAttributes {attributes :: Attributes}
  deriving (Generic)
  deriving newtype (ToJSON)


flatAttributes :: Element -> FlatAttributes
flatAttributes t =
  FlatAttributes
    $ addClass (mconcat t.classes) t.attributes
 where
  addClass [] atts = atts
  addClass cx atts = M.insert "class" (classAttValue cx) atts

  classAttValue :: [Class] -> T.Text
  classAttValue cx =
    T.intercalate " " $ fmap className cx
