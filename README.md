<div id="container">
    <img alt=NeoDo" src="assets/neodo_logo.png" />
</div>

## Do your project jobs

The plugin is aimed to executing project specific tasks or jobs based on project type.
When you open your project file, `neodo` will try to find project root and project type based on the project types configuration.

When project root/type is detected the `on_attach` function defined for specific project type is executed. This function is useful for create project specific bindings. For example `build`, `test` targets.

## Example

TODO

## Configuration
 
TODO

## Supported project types

TODO

## Feature/Road map

- Support for project specific configuration
- Integration with already available language tools like: `rust-tools`, `neovim-cmake`, etc...
