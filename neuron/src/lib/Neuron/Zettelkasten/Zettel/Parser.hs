{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Neuron.Zettelkasten.Zettel.Parser where

import Control.Monad.Writer
import Data.List (nub)
import Data.Some
import Data.TagTree (Tag)
import qualified Data.Text as T
import Neuron.Reader.Type
import Neuron.Zettelkasten.ID
import Neuron.Zettelkasten.Query.Error
import Neuron.Zettelkasten.Query.Parser (queryFromURILink)
import Neuron.Zettelkasten.Zettel
import qualified Neuron.Zettelkasten.Zettel.Meta as Meta
import Reflex.Dom.Pandoc.URILink (queryURILinks)
import Relude
import Text.Pandoc.Definition (Pandoc)
import Text.Pandoc.Util

parseZettel ::
  ZettelFormat ->
  ZettelReader ->
  FilePath ->
  ZettelID ->
  Text ->
  ZettelC
parseZettel format zreader fn zid s = do
  case zreader fn s of
    Left parseErr ->
      Left $ Zettel zid format fn "Unknown" False [] Nothing False [] parseErr s
    Right (meta, doc) ->
      let (title, titleInBody) = case Meta.title =<< meta of
            Just tit -> (tit, False)
            Nothing -> fromMaybe ("Untitled", False) $ do
              ((,True) . plainify . snd <$> getH1 doc)
                <|> ((,False) . takeInitial . plainify <$> getFirstParagraphText doc)
          metaTags = fromMaybe [] $ Meta.tags =<< meta
          date = Meta.date =<< meta
          unlisted = fromMaybe False $ Meta.unlisted =<< meta
          (queries, errors) = runWriter $ extractQueries doc
          queryTags = getInlineTag `mapMaybe` queries
          tags = nub $ metaTags <> queryTags
       in Right $ Zettel zid format fn title titleInBody tags date unlisted queries errors doc
  where
    -- Extract all (valid) queries from the Pandoc document
    extractQueries :: MonadWriter [QueryParseError] m => Pandoc -> m [Some ZettelQuery]
    extractQueries doc =
      fmap catMaybes $
        forM (queryURILinks doc) $ \ul ->
          case queryFromURILink ul of
            Left e -> do
              tell [e]
              pure Nothing
            Right v ->
              pure v
    getInlineTag :: Some ZettelQuery -> Maybe Tag
    getInlineTag = \case
      Some (ZettelQuery_TagZettel tag) -> Just tag
      _ -> Nothing
    takeInitial =
      (<> " ...") . T.take 18

-- | Like `parseZettel` but operates on multiple files.
parseZettels ::
  [((ZettelFormat, ZettelReader), [(ZettelID, FilePath, Text)])] ->
  [ZettelC]
parseZettels filesPerFormat =
  flip concatMap filesPerFormat $ \((format, zreader), files) ->
    flip fmap files $ \(zid, path, s) ->
      parseZettel format zreader path zid s
