import React, { useState } from 'react';
import {
  View,
  TextInput,
  Button,
  Image,
  Alert,
  StyleSheet,
  ScrollView,
} from 'react-native';
import { launchImageLibrary } from 'react-native-image-picker';
import storage from '@react-native-firebase/storage';
import { addProduct } from '../services/firebaseService';
import uuid from 'react-native-uuid';

const CreateProductScreen = ({ navigation }: any) => {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [price, setPrice] = useState('');
  const [stock, setStock] = useState('');
  const [category, setCategory] = useState('');
  const [image, setImage] = useState<any>(null);
  const [uploading, setUploading] = useState(false);

  const pickImage = async () => {
    const result = await launchImageLibrary({ mediaType: 'photo' });
    if (result.assets && result.assets.length > 0) {
      setImage(result.assets[0]);
    }
  };

  const handleSubmit = async () => {
    if (!title || !description || !price || !stock || !category || !image) {
      Alert.alert('Please fill all fields');
      return;
    }

    setUploading(true);

    try {
      const fileName = uuid.v4().toString();
      const ref = storage().ref(`/products/${fileName}`);
      await ref.putFile(image.uri);
      const imageUrl = await ref.getDownloadURL();

      await addProduct({
        title,
        description,
        price: parseFloat(price),
        imageUrl,
        stock: parseInt(stock),
        category,
      });

      Alert.alert('Success', 'Product added!');
      navigation.goBack();
    } catch (error: any) {
      Alert.alert('Error', error.message);
    } finally {
      setUploading(false);
    }
  };

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <TextInput placeholder="Title" value={title} onChangeText={setTitle} style={styles.input} />
      <TextInput
        placeholder="Description"
        value={description}
        onChangeText={setDescription}
        multiline
        style={styles.input}
      />
      <TextInput
        placeholder="Price"
        value={price}
        onChangeText={setPrice}
        keyboardType="decimal-pad"
        style={styles.input}
      />
      <TextInput
        placeholder="Stock"
        value={stock}
        onChangeText={setStock}
        keyboardType="numeric"
        style={styles.input}
      />
      <TextInput placeholder="Category" value={category} onChangeText={setCategory} style={styles.input} />
      <Button title="Pick Image" onPress={pickImage} />
      {image && <Image source={{ uri: image.uri }} style={styles.image} />}
      <Button title="Add Product" onPress={handleSubmit} disabled={uploading} />
    </ScrollView>
  );
};

export default CreateProductScreen;

const styles = StyleSheet.create({
  container: {
    padding: 20,
  },
  input: {
    borderBottomWidth: 1,
    marginBottom: 15,
    fontSize: 16,
    padding: 10,
  },
  image: {
    width: '100%',
    height: 200,
    marginVertical: 10,
  },
});
