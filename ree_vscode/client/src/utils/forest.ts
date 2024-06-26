import { Tree } from 'web-tree-sitter'
import TreeSitterFactory from './TreeSitterFactory'
import * as Parser from 'web-tree-sitter'

export interface IForest {
  getTree(uri: string): Tree
  createTree(uri: string, content: string): Tree
  updateTree(uri: string, content: string): Tree
  deleteTree(uri: string): boolean
}

class Forest implements IForest {
  public parser: Parser
  public language: Parser.Language
  private readonly trees: Map<string, Tree>

  constructor() {
    this.trees = new Map()
    TreeSitterFactory.build().then((p) => {
      this.parser = p
      this.language = p.getLanguage()
    })
  }

  public getTree(uri: string): Tree {
    return this.trees.get(uri)!
  }

  public createTree(uri: string, content: string): any {
    const tree: Tree = this.parser.parse(content)
    this.trees.set(uri, tree)

    return tree
  }

  // For the time being this is a full reparse for every change
  // Once we can support incremental sync we can use tree-sitter's
  // edit functionality
  public updateTree(uri: string, content: string): Tree {
    let tree: Tree = this.getTree(uri) || undefined
    if (tree !== undefined) {
      tree = this.parser.parse(content)
      this.trees.set(uri, tree)
    } else {
      tree = this.createTree(uri, content)
    }

    return tree
  }

  public deleteTree(uri: string): boolean {
    const tree = this.getTree(uri)
    if (tree !== undefined) {
      tree.delete()
    }
    return this.trees.delete(uri)
  }

  public release(): void {
    this.trees.forEach(tree => tree.delete())
    this.parser.delete()
  }
}
 
export const forest = new Forest()

export interface Link {
  name: string,
  body: string,
  as: string,
  imports: string[],
  from: string,
  isSymbol: boolean,
  queryMatch: Parser.QueryMatch
}

export const importRegexp = /(import\:\s)?(\-\>\s?\{(?<import>.+)\})/
export const asRegexp = /as\:\s\:(\w+)/
export const fromRegexp = /from\:\s(?<from>(\:\w+)|((\'|\")\w+(\/\w+)*(\'|\")))/

export function mapLinkQueryMatches(matches: Parser.QueryMatch[]): Array<Link> {
  return matches.map(qm => {
    let from = null
    let name = qm.captures[1].node.text
    let body = qm.captures[0].node.text
    let as = body.match(asRegexp)?.[1]
    let importsString = body.match(importRegexp)?.groups?.import
    let imports = []
    if (importsString) {
      imports = importsString.trim().split(' & ')
    }
    let isSymbol = name[0] === ":"
    name = name.replace(/\"|\'|\:/g, '') 

    if (isSymbol) {
      from = qm.captures[0].node.text.match(fromRegexp)?.groups?.from
    } else {
      from = name.split('/')[0]
    }
    from = from?.replace(/\"|\'|\:/g, '')

    return { name: name, body: body, as: as, imports: imports, isSymbol: isSymbol, from: from, queryMatch: qm }
  })
}