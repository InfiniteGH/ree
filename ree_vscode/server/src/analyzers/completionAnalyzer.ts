import { CompletionItem, CompletionItemKind } from 'vscode-languageserver'
import { Position } from 'vscode-languageserver-textdocument'
import { documents } from '../documentManager'
import { findTokenNodeInTree, forest, mapLinkQueryMatches } from '../forest'
import { Query, SyntaxNode, Tree, QueryCapture } from 'web-tree-sitter'
import { getCachedIndex, getGemDir, IPackagesSchema, ICachedIndex, isCachedIndexIsEmpty, buildObjectArguments } from '../utils/packagesUtils'
import { getPackageNameFromPath, getProjectRootDir, getObjectNameFromPath } from '../utils/packageUtils'
import { extractToken } from '../utils/tokenUtils'
import { logInfoMessage, snakeToCamelCase } from '../utils/stringUtils'

const url = require('node:url')

export default class CompletionAnalyzer {
  public static analyze(uri: string, position: Position): CompletionItem[] {
    return this.getFilteredCompletionList(uri, position)
  }

  private static getFilteredCompletionList(uri: string, position: Position): CompletionItem[] {
    const defaultCompletion : CompletionItem[] = []
    let filePath = ''

    try {
      filePath = url.fileURLToPath(uri)
    } catch (err: unknown) {
      if (err instanceof TypeError && err.message === 'The URL must be of scheme file') {
        filePath = uri
        const index = getCachedIndex()
        if (isCachedIndexIsEmpty()) {
          logInfoMessage('Index is empty in completionAnalyzer')
          return defaultCompletion
        } 

        const packagesSchema = index.packages_schema
        if (!packagesSchema) { return defaultCompletion }

        const currentPackageName = ''

        const projectRootDir = getProjectRootDir(filePath)
        if (!projectRootDir) { return defaultCompletion }

        const currentProjectPackages = this.getCurrentProjectPackages(packagesSchema, projectRootDir, currentPackageName, filePath, null)
        const gemPackageObjects = this.getGemPackageObjects(packagesSchema, projectRootDir, currentPackageName, filePath, null)
        return currentProjectPackages.concat(...gemPackageObjects)
      } else {
        throw err
      }
    }

    const index = getCachedIndex()
    if (isCachedIndexIsEmpty()) {
      logInfoMessage('Index is empty in completionAnalyzer')
      return defaultCompletion
    } 

    const token = extractToken(uri, position)
    if (!token) { return defaultCompletion }

    const packagesSchema = index.packages_schema
    if (!packagesSchema) { return defaultCompletion }

    const currentPackageName = getPackageNameFromPath(filePath)
    if (!currentPackageName) { return defaultCompletion }

    const projectRootDir = getProjectRootDir(filePath)
    if (!projectRootDir) { return defaultCompletion }

    const objectName = getObjectNameFromPath(filePath)
    if (!objectName) { return defaultCompletion }

    const doc = documents.get(uri)
    let tree = forest.getTree(uri)
    if (!tree) {
      tree = forest.createTree(uri, doc.getText())
    }

    // filter that already using
    const query = tree.getLanguage().query(
      `(
        (link
           link_name: (_) @name) @link
        (#select-adjacent! @link)
      ) `
    ) as Query

    const links = mapLinkQueryMatches(query.matches(tree.rootNode))

    const constantsQueryCaptures = tree.getLanguage().query(
      `(
        (constant) @call
        (#match? @call "(${links.filter(l => l.imports.length > 0).map(l => l.imports).flat().join("|")})$")
      )`
    ).captures(tree.rootNode)

    const tokenNode = findTokenNodeInTree(token, tree, position)

    // first we check if we have any matching nodes
    if (tokenNode) {
      if (index && index?.classes) {
        const constantMethods = this.getConstantMethodsFromIndex(tokenNode, index, constantsQueryCaptures)
        if (constantMethods.length > 0) {
          return constantMethods
        }

        const objectMethods = this.getObjectMethodsFromIndex(tree, tokenNode, index)
        if (objectMethods.length > 0) {
          return objectMethods
        }
      }
    }
  
    // if there are no matching nodes, show package objects and constants
    const currentProjectPackages = this.getCurrentProjectPackages(packagesSchema, projectRootDir, currentPackageName, filePath, tokenNode)
    const gemPackageObjects = this.getGemPackageObjects(packagesSchema, projectRootDir, currentPackageName, filePath, tokenNode)
    let allItems = currentProjectPackages.concat(...gemPackageObjects)

    // add constants
    if (index && index?.classes) {
      const constantsItems = this.getConstantsFromIndex(index, projectRootDir, currentPackageName, filePath)
      allItems = allItems.concat(...constantsItems)
    }

    if (allItems.length === 0) { return defaultCompletion }

    let linkNames = links.map(l => l.name)
    return allItems.filter(obj => !linkNames.includes(obj.label) || obj.label !== objectName)
  }

  private static getCurrentProjectPackages(
    packagesSchema: IPackagesSchema,
    projectRootDir: string,
    currentPackage: string,
    filePath: string,
    tokenNode: SyntaxNode | null
  ): CompletionItem[] {
    return packagesSchema.packages.map((pckg) => {
      let objects = pckg.objects.map(obj => (
          {
            label: obj.name,
            labelDetails: {
              description: `from: ${pckg.name}`
            },
            kind: CompletionItemKind.Method,
            insertText: buildObjectArguments(obj, tokenNode),
            data: {
              objectSchema: obj.schema_rpath,
              isGem: false,
              fromPackageName: pckg.name,
              toPackageName: currentPackage,
              currentFilePath: filePath,
              type: CompletionItemKind.Method,
              projectRootDir: projectRootDir
            }
          } as CompletionItem
        )
      )

      return objects
    }).flat()
  }

  private static getGemPackageObjects(
    packagesSchema: IPackagesSchema,
    projectRootDir: string,
    currentPackageName: string,
    filePath: string,
    tokenNode: SyntaxNode | null
    ): CompletionItem[] {
      return packagesSchema.gem_packages.map((pckg) => {
        let gemPath = getGemDir(pckg.name)
        if (!gemPath) { return [] }

        let objects = pckg.objects.map(obj => (
            {
              label: obj.name,
              labelDetails: {
                description: `from: ${pckg.name}`
              },
              kind: CompletionItemKind.Method,
              insertText: buildObjectArguments(obj, tokenNode),
              data: {
                objectSchema: obj.schema_rpath,
                fromPackageName: pckg.name,
                isGem: true,
                toPackageName: currentPackageName,
                currentFilePath: filePath,
                type: CompletionItemKind.Method,
                projectRootDir: gemPath || projectRootDir
              }
            }
          )
        )

        return objects
      }).flat()
  }

  private static getConstantsFromIndex(
    index: ICachedIndex,
    projectRootDir: string,
    currentPackageName: string,
    filePath: string
    ): CompletionItem[] {
    return Object.keys(index.classes).map((k: string) => {
      return index['classes'][k].map(c => {
        return {
          label: k,
          labelDetails: {
            description: `from: :${c.package}`
          },
          kind: CompletionItemKind.Class,
          data: {
            objectName: k,
            fromPackageName: c.package,
            toPackageName: currentPackageName,
            projectRootDir: projectRootDir,
            currentFilePath: filePath,
            type: CompletionItemKind.Class,
            linkPath: c.path
          }
        } as CompletionItem
      })
    }).flat()
  }

  private static getConstantMethodsFromIndex(
    tokenNode: SyntaxNode,
    index: ICachedIndex,
    constantsQueryCaptures: QueryCapture[]
    ): CompletionItem[] {
    // check if we inside constant instantiation
    let constantNodeText = tokenNode?.parent?.parent?.firstChild?.text
    let classes = Object.keys(index.classes)
    if (constantNodeText && classes.includes(constantNodeText)) {
      return index.classes[constantNodeText].map(c => {
        return c.methods.map(m => {
          return {
            label: m.name,
            details: `${snakeToCamelCase(c.package)}`,
            kind: CompletionItemKind.Field,
            insertText: this.buildMethodInsertString(m)
          } as CompletionItem
        })
      }).flat()
    }

    const findParentNodeWithType = (node: SyntaxNode | null, type: string, returnParent: boolean = false): SyntaxNode | null => {
      if (node === null) { return node }
      if (!node.parent) { return node }
      if (node.parent.type === type) { return returnParent ? node.parent : node }

      return findParentNodeWithType(node.parent, type, returnParent)
    }

    // trying to match call-nodes (ex SomeClass.new().some_method_call)
    let constantCallQueryMatches = constantsQueryCaptures.filter(e => e.node?.parent?.type === 'call')
    let constantsFromIndexNodes = constantCallQueryMatches.filter(e => classes.includes(e.node.text)).map(e => e.node)
    let matchedNodes = constantsFromIndexNodes.filter(node => {
      // if tokenNode inside constantNode parent
      // ex: SomeClass.new(id: 1).*tokenNode* or SomeClass.new(id: 1).build.*tokenNode*
      let nodeHaveTokenNode = !!findParentNodeWithType(node, 'assignment', false)?.children.find(c => c.equals(tokenNode)) ||
                              !!findParentNodeWithType(node, 'method', false)?.children.find(c => c.equals(tokenNode))
      if (nodeHaveTokenNode) {
        return true
      } else {
        // check if we have assignment node, then check if assignment lhs is same as tokenNode
        const assignmentNode = findParentNodeWithType(node, 'assignment', true)
        if (assignmentNode && assignmentNode.type !== 'program') {
          return !!tokenNode?.parent?.text.match(RegExp(`^${assignmentNode?.firstChild?.text}\\.`))
        }
      }
    })
    if (matchedNodes.length > 0) {
      return matchedNodes.map(n => {
        return index.classes[n.text].map(c => {
          return c.methods.map(m => {
            return {
              label: m.name,
              details: `${snakeToCamelCase(c.package)}`,
              kind: CompletionItemKind.Field,
              insertText: this.buildMethodInsertString(m)
            } as CompletionItem
          })
        }).flat()
      }).flat()
    }

    return [] as CompletionItem[]
  }

  private static getObjectMethodsFromIndex(
    tree: Tree,
    tokenNode: SyntaxNode,
    index: ICachedIndex
  ): CompletionItem[] {
    let objects = Object.keys(index.objects)

    const query = tree.getLanguage().query(
      `(
        (link
            link_name: (_) @name) @link
        (#select-adjacent! @link)
      ) `
    ) as Query

    const links = mapLinkQueryMatches(query.matches(tree.rootNode))
    const linksQuery = tree.getLanguage().query(
      `(
        (identifier) @call
        (#match? @call "(${links.filter(l => l.isSymbol).map(l => l.name).flat().join("|")})$")
      )`
    ) as Query

    const checkParent = (node: SyntaxNode, targetNode: SyntaxNode): SyntaxNode | null => {
      if (node === null) { return null }
      if (node.children.find(c => c.equals(targetNode))) { return node }
      if (!node.parent) { return null }
      if (node.parent && (node.parent?.firstChild?.type === 'def' || node.parent?.firstChild?.type === 'do')) { return null }
      
      return checkParent(node.parent, targetNode)
    }

    let identifiersCallQueryMatches = linksQuery.captures(tree.rootNode).filter(e => e.node?.parent?.type === 'call')
    let objectsFromIndexNodes = identifiersCallQueryMatches.filter(e => objects.includes(e.node.text)).map(e => e.node)

    let objectMatchedNodes = objectsFromIndexNodes.filter(node => {
      // if tokenNode inside parent children
      // ex: someDao.active.*tokenNode*
      let nodeHaveTokenNode = !!checkParent(node, tokenNode)
      if (nodeHaveTokenNode) { return true }

      return false
    })

    if (objectMatchedNodes.length > 0) {
      const objMethods = objectMatchedNodes.map(n => {
        return index.objects[n.text].map(c => {
          return c.methods.map(m => {
            return {
              label: m.name,
              details: `${snakeToCamelCase(c.package)}`,
              kind: CompletionItemKind.Method,
              insertText: this.buildMethodInsertString(m)
            } as CompletionItem
          })
        }).flat()
      }).flat() as CompletionItem[]

      return objMethods
    }

    return []
  }

  private static buildMethodInsertString(method: any): string {
    const params = method.parameters
    if (method?.parameters?.length > 0) {
      return `${method.name}(${params.map((p: any) => p.name).join(', ')})`
    }
    return method.name
  }
}


