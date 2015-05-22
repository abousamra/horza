# Get

Dynamically generate classes to encapsulate common database queries in Rails.

## Why is this necessary?

#### Problem 1: Encapsulation

ORMs like ActiveRecord make querying the database incredible easy, but with power comes responsibility, and there's a lot of irresponsible code out there.

Consider:

```ruby
User.where(name: 'blake').order('updated_at DESC').limit(2)
```

This query is easy to read, and it works. Unfortunately, anything that uses it is tough to test, and any other implementation has to repeat this same cumbersome method chain.
Sure, you can wrap it in a method:

```ruby
def find_two_blakes
  User.where(name: 'blake').order('updated_at DESC').limit(2)
end
```

But where does it live? Scope methods on models are (IMHO) hideous, so maybe a Helper? A Service? A private method in a class that I inherit from? The options aren't great.

#### Problem 2: Associations

ORMs like ActiveRecord also makes querying associations incredible easy. Consider:

```html+ruby
<div>
  <ul>
    <% current_user.employer.sportscars.each do |car| %>
      <li><%= car.cost %></li>
    <% end >
  </ul>
</div>
```

The above is a great example of query pollution in the view layer. It's quick-to-build, tough-to-test, and very common in Rails.
A spec for a view like this would need to either create/stub each of the records with the proper associations, or stub the entire method chain.

If you move the query to the controller, it's a bit better:

```ruby
# controller
def index
  @employer = current_user.employer
  @sportscars = @employer.sportscars
end
```

```html+ruby
#view
<div>
  <ul>
    <% @sportscars.each do |car| %>
      <li><%= car.cost %></li>
    <% end >
  </ul>
</div>
```

But that's just lipstick on a pig. We've simply shifted the testing burden to the controller; the dependencies and mocking complexity remain the same.

#### Problem 3: Self-Documenting code

Consider:

```ruby
User.where(last_name: 'Turner').order('id DESC').limit(1)
```

Most programmers familiar with Rails will be able to understand the above immediately, but only because they've written similar chains a hundred times.

## Solution

The Get library tries to solve the above problems by dynamically generating classes that perform common database queries.
Get identifies four themes in common queries:

- **Singular**: Queries that expect a single record in response
- **Plural**: Queries that expect a collection of records in response
- **Query**: Query is performed on the given model
- **Association**: Query traverses the associations of the given model and returns a different model

These themes are not mutually exclusive; **Query** and **Association** can be either **Singular** or **Plural**.

## Usage

#### Singular Queries - Return a single record

With field being queried in the class name
```ruby
Get::UserById.run(123)
```

Fail loudly
```ruby
Get::UserById.run!(123)
```

Slightly more flexible model:
```ruby
Get::UserBy.run(id: 123, employer_id: 88)
```

#### Plural Queries - Return a collection of records

_Note the plurality of 'Users'_
```ruby
Get::UsersByLastName.run('Turner')
```

#### Associations

Associations use 'From', and are sugar for the chains we so often write in rails.

_You can pass either an entity or an id, the only requirement is that it responds to #id_

Parent relationship (user.employer):
```ruby
Get::EmployerFromUser.run(user)
```

Child relationship (employer.users):
```ruby
Get::UsersFromEmployer.run(employer_id)
```

Complex relationship (user.employer.sportscars)
```ruby
Get::SportscarsFromUser.run(user, via: :employer)
```

Keep the plurality of associations in mind. If an Employer has many Users, UsersFromEmployer works,
but UserFromEmployer will throw `Get::Errors::InvalidAncestry`.

## Entities

Ironically, one of the "features" of Get is its removal of the ability to query associations from the query response object.
This choice was made to combat query pollution throughout the app, particularly in the view layer.

To achieve this, Get returns **entities** instead of ORM  objects (`ActiveRecord::Base`, etc.).
These entity classes are generated at runtime with names appropriate to their contents.
You can also register your own entities in the Get config.

```ruby
>> result = Get::UserById.run(user.id)
>> result.class.name
>> "Get::Entities::GetUser"
```

Individual entities will have all attributes accessible via dot notation and hash notation, but attempts to get associations will fail.
Collections have all of the common enumerator methods: `first`, `last`, `each`, and `[]`.

Dynamically generated Get::Entities are prefixed with `Get` to avoid colliding with your ORM objects.

## Testing

A big motivation for this library is to make testing database queries easier.
Get accomplishes this by making class-level mocking/stubbing very easy.

Consider:

```ruby
# sportscars_controller.rb

# ActiveRecord
def index
  @sportscars = current_user.employer.sportscars
end

# Get
def index
  @sportscars = Get::SportscarsFromUser.run(current_user, via: employer)
end
```

The above methods do the exact same thing. Cool, let's test them:

```ruby
# sportscars_controller.rb
describe SportscarsController, type: :controller do
  context '#index' do
    context 'ActiveRecord' do
      let(:user) { FactoryGirl.build_stubbed(:user, employer: employer) }
      let(:employer) { FactoryGirl.build_stubbed(:employer) }
      let(:sportscars) { 3.times { FactoryGirl.build_stubbed(:sportscars) } }

      before do
        employer.sportscars << sportscars
        sign_in(user)
        get :index
      end

      it 'assigns sportscars' do
        expect(assigns(:sportscars)).to eq(sportscars)
      end
    end

    context 'Get' do
      let(:user) { FactoryGirl.build_stubbed(:user, employer: employer) }
      let(:sportscars) { 3.times { FactoryGirl.build_stubbed(:sportscars) } }

      before do
        allow(Get::SportscarsFromUser).to receive(:run).and_return(sportscars)
        sign_in(user)
        get :index
      end

      it 'assigns sportscars' do
        expect(assigns(:sportscars)).to eq(sportscars)
      end
    end
  end
end
```

By encapsulating the query in a class, we're able to stub it at the class level, which eliminates then need to create any dependencies.
This will speed up tests (a little), but more importantly it makes them easier to read and write.

## Config

**Define your adapter**

_config/initializers/ask.rb_
```ruby
Get.configure { |config| config.adapter = :active_record }
```

**Configure custom entities**

The code below will cause Get classes that begin with _Users_ (ie. `UsersByLastName`) to return a MyCustomEntity instead of the default `Get::Entities::User`.

_config/initializers/ask.rb_
```ruby
class MyCustomEntity < Get::Entities::Collection
 def east_london_length
   "#{length}, bruv"
 end
end

Get.config do |config|
 config.register_entity(:users_by_last_name, MyCustomEntity)
end
```

You can reset the config at any time using `Get.reset`.

## Adapters

Get currently works with ActiveRecord.

## Benchmarking

Get requests generally run < 1ms slower than ActiveRecord requests.

```
GETTING BY ID, SAMPLE_SIZE: 400


>>> ActiveRecord
                                     user     system      total        real
Clients::User.find               0.170000   0.020000   0.190000 (  0.224373)
Clients::User.find_by_id         0.240000   0.010000   0.250000 (  0.342278)

>>> Get
                                     user     system      total        real
Get::UserById                    0.300000   0.020000   0.320000 (  0.402454)
Get::UserBy                      0.260000   0.010000   0.270000 (  0.350982)


GETTING SINGLE RECORD BY LAST NAME, SAMPLE_SIZE: 400


>>> ActiveRecord
                                     user     system      total        real
Clients::User.where              0.190000   0.020000   0.210000 (  0.292516)
Clients::User.find_by_last_name  0.180000   0.010000   0.190000 (  0.270033)

>>> Get
                                     user     system      total        real
Get::UserByLastName              0.240000   0.010000   0.250000 (  0.337908)
Get::UserBy                      0.310000   0.020000   0.330000 (  0.415142)


GETTING MULTIPLE RECORDS BY LAST NAME, SAMPLE_SIZE: 400


>>> ActiveRecord
                                     user     system      total        real
Clients::User.where              0.020000   0.000000   0.020000 (  0.012604)

>>> Get
                                     user     system      total        real
Get::UsersByLastName             0.100000   0.000000   0.100000 (  0.105822)
Get::UsersBy                     0.100000   0.010000   0.110000 (  0.106406)


GETTING PARENT FROM CHILD, SAMPLE_SIZE: 400


>>> ActiveRecord
                                     user     system      total        real
Clients::User.find(:id).employer  0.440000   0.030000   0.470000 (  0.580800)

>>> Get
                                     user     system      total        real
Get::EmployerFromUser            0.500000   0.020000   0.520000 (  0.643316)


GETTING CHILDREN FROM PARENT, SAMPLE_SIZE: 400


>>> ActiveRecord
                                     user     system      total        real
Clients::Employer.find[:id].users  0.160000   0.020000   0.180000 (  0.218710)

>>> Get
                                     user     system      total        real
Get::UsersFromEmployer           0.230000   0.010000   0.240000 (  0.293037)


STATS

AVERAGE DIFF FOR BY ID: 0.000233s
AVERAGE DIFF FOR BY LAST NAME: 0.000238s
AVERAGE DIFF FOR BY LAST NAME (MULTIPLE): 0.000234s
AVERAGE DIFF FOR PARENT FROM CHILD: 0.000156s
AVERAGE DIFF FOR CHILDREN FROM PARENT: -0.000186s
```
